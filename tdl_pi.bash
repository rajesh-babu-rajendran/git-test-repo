#!/bin/bash
######################################################################
#
# Torrrent downloader shell script
#
#######################################################################

# Search URL
SURL="https://thepiratebay.org/top/601"

# Download Url
DURL=${SURL}
REDIS='redis-cli'

# No of pages to download from the server
for page in 0
do

	 # Form the download Url
	 if [ ${page} -ne 0 ]
	 then
	   DURL=$(echo "$SURL&p="${page})
	 fi

	 echo "Downloading file "${DURL}

	 DFILE=tmp.${page}
	 TFILE=${DFILE}.tmp

	 wget --output-document=${DFILE} ${DURL}
	 if [ $? -ne 0 ] 
	 then 
	   echo 'Download failed ';
	   exit 0
	 fi

	 cat ${DFILE} | sed -n -f tdl_clean.sed > ${TFILE}
	  
	 IFS='
'
	 
	 # Add torrents 
	 TR_CMD="transmission-remote"
	 TR_USR="transmission"
	 TR_PWD="transmission"
	 

	 #############################################################################
	 ## Add torrents to download
	 #############################################################################

	 for line in $(cat $TFILE)
	 do
	  # For each line
	  TR_HASH=$(echo ${line} | awk -F\| '{print $1}')
	  TR_DESC=$(echo ${line} | awk -F\| '{print $2}')
	 
	  # Check if the HASH is available in Cache
	  RSP=$(${REDIS} get ${TR_HASH})
	  
	  if [ "${RSP}" = "" ]
	  then
	     # Start the transmission
	     echo "Starting transmission for ${TR_DESC} with ${TR_HASH}"

	     TR_MAGNET="magnet:?xt=urn:btih:${TR_HASH}"	
	    
	     # Add the torrent 
	     ${TR_CMD} -n "${TR_USR}:${TR_PWD}" -a ${TR_MAGNET}
	    
	     # Start the torrent
	     ${TR_CMD} -n "${TR_USR}:${TR_PWD}" -t ${TR_HASH} -s

	     # Save the Description
	     ${REDIS} set "${TR_HASH}" "${TR_DESC}" 2>&1 > /dev/null

	   fi
	  
	  done 

	  #############################################################################
	  # check the progress of the torrents download
	  #############################################################################

	  TR_CNT=$(${TR_CMD} -n "${TR_USR}:${TR_PWD}" -l | wc -l)

	  while [ ${TR_CNT} -ne 2 ]   
	  do
            echo "Sleeping for 30 seconds "
	    sleep 30;
	    # check if the torrent has downloaded
	    for info in $(${TR_CMD} -n "${TR_USR}:${TR_PWD}" -l | awk '/^ /{print $1"~"$2}')
	    do
	      TR_ID=$(echo ${info} | awk -F"~" '{print $1}' | sed 's/ //g')
	      TR_PC=$(echo ${info} | awk -F"~" '{print $2}' | sed 's/ //g')
	      TR_BITH=$(${TR_CMD} -n "${TR_USR}:${TR_PWD}" -t ${TR_ID} -i | awk -F":" '/Hash/{print $2}' | sed 's/ //g')

              echo "Torrent ${TR_ID} is ${TR_PC} with ${TR_BITH}"

	      # Get the Info about the torrent    
	      for trinfo in $(${TR_CMD} -n "${TR_USR}:${TR_PWD}" -t ${TR_ID} -i | awk -F":" '/^ /{print $1"~"$2}')
	      do
		 TR_INFO_KEY=$(echo ${trinfo} | awk -F"~" '{print $1}' | sed 's/ //g' )
		 TR_INFO_VAL=$(echo ${trinfo} | awk -F"~" '{print $2}' | sed 's/ //g' )

		 ${REDIS} set "${TR_BITH}-${TR_INFO_KEY}" "${TR_INFO_VAL}" 2>&1 > /dev/null
	      done

	      if [ "${TR_PC}" = "100%" ]
	      then
		# Remove the torrent
		${TR_CMD} -n "${TR_USR}:${TR_PWD}" -t ${TR_ID} -r 
	      fi
	      
	    done
            
            # Finally update the count
            TR_CNT=$(${TR_CMD} -n "${TR_USR}:${TR_PWD}" -l | wc -l) 
	    
	  done

	  #############################################################################
	  ## End of check the progress of the torrents download
	  #############################################################################
	 

done
