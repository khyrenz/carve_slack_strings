#!/bin/bash

scriptname=`basename "$0"`

if [ "$#" -lt 1 ]; then
	echo
	echo -e "Usage:\c"
	echo -e '\t' $scriptname "<input file>" # [<output file>]"
	echo
	echo "Note that only the first (and optional second) argument will be used; any extras will be ignored"
	#echo "If no output file is specified, default is to output to 'carved_slack_strings.txt' in the current folder"
	echo
	exit
#elif [ "$#" -lt 2 ]; then
#	infile=$1
#	outfile="carved_slack_strings.txt"
else
	infile=$1
#	outfile=$2
fi

echo
echo "Carving Slack artefacts out of $infile..."
#echo "Writing output to $outfile"

#Keywords to search for to carve out Slack info:
#Channel ID | info: Store: SELECT_CHANNEL
#Channel Name | New message in #
#Chat user & message text | <text hint-maxLines="10" hint-style="bodySubtle" hint-wrap="true">

#String manipulation reminder:
#str="STR: This is a long string with a delimiter</end><start>STR2: Another string</end2><start2>STR3: And Again></end3>"
#String BEFORE FIRST instance of '<'
#echo ${str%%"<"*}
#String BEFORE LAST instance of '<'
#echo ${str%"<"*}
#String AFTER LAST instance of '<'
#echo ${str##*"<"}
#String AFTER FIRST instance of '<'
#echo ${str#*"<"}

OFS=$IFS
IFS=$'\n'

#Searching for keywords in 'infile'
#Searching for user info
user_info=$(grep -a -B1 "\"user_id\":\"" $infile)
#echo $user_info #debug
user_id_list=$(echo $user_info | grep -Eaoh "\"user_id\":\"[A-Za-z0-9 _$£&#\-]+\"")
user_name_list=$(echo $user_info | grep -Eaoh "\"name\":\"[A-Za-z0-9 _$£&#\-]+\"")
user_id=""
user_name=""

for uid in $user_id_list; do
	uid=$(echo $uid | cut -d':' -f2 | sed 's/\"//g' | sed -n 1p)
	if [[ $user_id != *$uid* ]]; then
		#echo $uid #debug
		if [ ! -n "$user_id" ]; then
			user_id=$uid
		else
			user_id=$user_id", "$uid
		fi
	fi
done
for uname in $user_name_list; do
	uname=$(echo $uname | cut -d':' -f2 | sed 's/\"//g' | sed -n 1p)
	if [[ $user_name != *$uname* ]]; then
		#echo $uname #debug
		if [ ! -n "$user_name" ]; then
			user_name=$uname
		else
			user_name=$user_name", "$uname
		fi
	fi
done

#user_id=$(echo $user_info | grep -Eaoh "\"user_id\":\"[A-Za-z0-9 _$£&#\-]+\"" | cut -d':' -f2 | sed 's/\"//g' | sed -n 1p)
#user_name=$(echo $user_info | grep -Eaoh "\"name\":\"[A-Za-z0-9 _$£&#\-]+\"" | cut -d':' -f2 | sed 's/\"//g' | sed -n 1p)
if [ -n "$user_id" ] && [ -n "$user_name" ]; then
	echo -e "User details found - ID:" $user_id"; Name:" $user_name #> $outfile
fi

#Searching for channel info
channel_id_lines=$(grep -a "info: Store: SELECT_CHANNEL" $infile)
channels_found=""
for ciline in $channel_id_lines; do
	#reset
	#echo $ciline #debug
	ciline=$(echo $ciline | tr -dc '[[:print:]]')
	channel_id=${ciline#*"info: Store: SELECT_CHANNEL"}
	#echo $channel_id #debug
	if [[ $channel_id == *"@"* ]]; then
		channel_id="$(echo -e "${channel_id}" | cut -d'@' -f1)"
	fi
	channel_id="$(echo -e "${channel_id}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' 2>/dev/null)"
	if [ -n "$channel_id" ] && [[ $channels_found != *$channel_id* ]]; then
		echo
		echo -e "Channel ID found: $channel_id" #>> $outfile
		channels_found=$channels_found"|"$channel_id
		#trying to match channel ID to name & get associated message info & content
		channel_info=$(grep -a "launch=\"slack://channel?id=${channel_id}&amp" $infile)
		if [ -n "$channel_info" ]; then
			channel_name=$(echo ${channel_info} | grep -aEoh "New message in #[a-zA-Z_ $£%&\.\-]+<")
			channel_name=${channel_name#*"New message in #"}
			channel_name=$(echo ${channel_name} | cut -d'<' -f1)
			if [ -n "$channel_name" ]; then
				echo -e "Channel Name: $channel_name" #>> $outfile
			fi
			
			workspace_id=$(echo ${channel_info} | grep -Eaoh "team=[A-Z0-9]+")
			workspace_id=${workspace_id#*"team="}
			workspace_id=${workspace_id%%"team="*}
			workspace_id=$(echo $workspace_id | tr '\n' '')
			if [ -n "$workspace_id" ]; then
				echo -e "Channel's Workspace ID: $workspace_id" #>> $outfile
			fi
		
			workspace_name=$(echo ${channel_info} | grep -Ea "title=\"")
			workspace_name=${workspace_name#*"title=\""}
			workspace_name=$(echo ${workspace_name} | cut -d$'\"' -f1)
			if [ -n "$workspace_name" ]; then
				echo -e "Workspace Name: $workspace_name" #>> $outfile
			fi
				
			#Looping through each line in channel_info based on \r as separator, then looking for message time & content to pair up
			IFS=$'\r'
			msg_texts_out=""
			num_messages=0
			num_duplicates=0
			
			for chline in $channel_info; do
				message_time=$(echo ${chline} | grep -Eaoh "message=[0-9]+")
				message_text=$(echo ${chline} | grep -Eaoh "<text hint-maxLines=\"10\" hint-style=\"bodySubtle\" hint-wrap=\"true\">[A-Za-z0-9:_ @\-\?$£\.,]+")

				message_time=${message_time#*"message="*}
				message_time="${message_time:0:10}"
				
				if [[ -n "$message_time" ]]; then
					message_time=$(date -ud @${message_time} +"%F %T UTC")
				else
					message_time=""
				fi
				message_text=${message_text#*">"*}
				
				if [ -n "$message_time" ] && [ -n "$message_text" ]; then
					if [[ $msg_texts_out != *"${message_time} - ${message_text}"* ]]; then
						msg_texts_out=$msg_texts_out";${message_time} - ${message_text}"
						echo ${message_time} - ${message_text} #>> $outfile
						((num_messages++))
					else
						((num_duplicates++))
					fi
				fi
			done
			echo "$num_messages Messages found for this Channel... $num_duplicates duplicate messages (based on time and content) removed" #>> $outfile
			IFS=$'\n'
		else
			workspace_id=$(grep -a -A5 "SELECT_CHANNEL ${channel_id}" "${infile}" | grep -a "\"teamId\":" | cut -d$'\n' -f1 | cut -d':' -f2 | sed -e 's/^[[:space:]]\"*//' -e 's/\"[[:space:]]*$//')
			if [ -n "$workspace_id" ]; then
				echo -e "Channel's Workspace ID: $workspace_id" #>> $outfile
			fi
			
			workspace_info=$(grep -a -C3 "${workspace_id}" "${infile}")
			if [ -n "$workspace_info" ]; then
				workspace_name=$(echo ${workspace_info} | grep -Ea "title=\"")
				workspace_name=${workspace_name#*"title=\""}
				workspace_name=$(echo ${workspace_name} | cut -d$'\"' -f1)
				if [ -n "$workspace_name" ]; then
					echo -e "Workspace Name: $workspace_name" #>> $outfile
				fi
				#workspace_url=$(echo ${workspace_info} | grep -Eaoh "https://[a-zA-Z_ $£%&\.\-]+slack.com" | cut -d$'\n' -f1 2>/dev/null)
				#if [ -n "$workspace_url" ]; then
				#	echo -e "Workspace URL: $workspace_url"
				#fi
			fi
		fi
	fi
done

IFS=$OFS


