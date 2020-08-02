#!/bin/sh
# sudheer@dexiva.com  - 09 Jul 2015
# Simple shell script to dynamically generate/update m3u8 files and chunks
# so that various sceanarios like stale manifest, missing chunks, chunk count
# changes etc. can be tested

# Usage: This program doesn't have any command line parameters, all are
# hard coded inside the code.
# Copy this program to the web directory and run this program as super user,
# And access test.m3u8

# While program is running, open another terminal window and create some files
# to simuluate the scenarios mentioned below (use #touch command to create files)
# 1. When you create a file called '/tmp/stale', stale manifest situaion will occur
# (just #touch /tmp/stale)
# 2. When you create a file called /tmp/http4xx some chunks will be missing and
# you should get 404 errors
# 3. When you create /tmp/chunkcountIncr, the chunk count in the manifest will increase. when you create /tmp/chunkcountDecr it will decrease
# 4. When you create a file called /tmp/chunkdelay we will make some of the
# chunk size to be very huge to make the download to take more time (Kludge)

# Known limitaiton: Multiple error conditions may not work.


# How fast the manifest files need to be updated
MANIFEST_GEN_DELAY_TIME=6

# How many TS Chunk entries in the manifest
TS_CHUNKS_COUNT=5
MEDIA_SEQ_NUM=1
DEF_PLAY_TIME=6
CHUNK_PLAY_TIME_FACTOR=5.9

STALE_STATUS_FILE=/tmp/stale
HTTP_4XX_STATUS_FILE=/tmp/http4xx
CHUNK_COUNT_INCR_STATUS_FILE=/tmp/chunkcountIncr
CHUNK_COUNT_DECR_STATUS_FILE=/tmp/chunkcountDecr
CHUNK_DELAY_STATUS_FILE=/tmp/chunkdelay
MANIFEST_STAGE_FILE=m3u8_stage.txt
LOG_FILE=/var/tmp/hlsSimul.log

# Do the clean up
rm -f $HTTP_4XX_STATUS_FILE
rm -f $STALE_STATUS_FILE
rm -f $CHUNK_COUNT_INCR_STATUS_FILE
rm -f $CHUNK_COUNT_DECR_STATUS_FILE
rm -f $CHUNK_DELAY_STATUS_FILE
rm -f $MANIFEST_STAGE_FILE
rm -f sample.ts
rm -f /tmp/*.4xx
rm -f /tmp/*.chunk*
rm -f /tmp/stale

# Create a sample.ts file - this will be our standard chunk file
# Easy way is to copy any binary file as sample.ts
# we copy /bin/echo binary for this which gives us size of 28Kb, if you need bigger
# size, repeat the below command few times

cat `which echo` >> sample.ts
cat `which echo` >> sample.ts
echo "`date`: Created the sample chunk file.."

while [ 1 ]; do

    # Continue with the same manifest  if the stale status file is available
    if [ -f $STALE_STATUS_FILE ]; then
        continue;
    fi

    # Create the usual info required..
    echo "`date`: Starting with Media Sequence $MEDIA_SEQ_NUM" | tee -a $LOG_FILE
    echo -e "#EXTM3U\n#EXT-X-VERSION:3\
        \n#EXT-X-TARGETDURATION:$DEF_PLAY_TIME\n " > $MANIFEST_STAGE_FILE
    echo -e "#EXT-X-MEDIA-SEQUENCE:$MEDIA_SEQ_NUM\n\n" >> $MANIFEST_STAGE_FILE

    CHUNK_ADDED=0

    while [ $CHUNK_ADDED -lt $TS_CHUNKS_COUNT ]; do
        # We provide some random timing to the chunk play time..
        let RANDOM_FACTOR=$RANDOM%100
        let CHUNK_NUMBER=$MEDIA_SEQ_NUM+$CHUNK_ADDED
        echo -e "#EXTINF:$CHUNK_PLAY_TIME_FACTOR$RANDOM_FACTOR"  >> $MANIFEST_STAGE_FILE
        echo -e "tsChunk$CHUNK_NUMBER.ts" >> $MANIFEST_STAGE_FILE
        echo "`date`: Added file tsChunk$CHUNK_NUMBER.ts to manifest " | tee -a $LOG_FILE
        let CHUNK_ADDED=$CHUNK_ADDED+1

        # Manage  number of chunks in this manifest
        if [ -f $CHUNK_COUNT_DECR_STATUS_FILE ] ; then
            # We need to put less number of chunks in this case, but do that
            # on a random basis
            let x=$RANDOM%3
            if [ $x -gt 1 ]; then
                echo "`date`: Added only $CHUNK_ADDED to the manifest insted of $TS_CHUNKS_COUNT " | tee -a $LOG_FILE
                break;
            fi
        fi
    done

    # if the chunk count status  file is enabled, add more chunks to this manifest
    if [ -f $CHUNK_COUNT_INCR_STATUS_FILE ]; then
        let x=$RANDOM%6
        while [ $x -gt 0 ]; do
            let RANDOM_FACTOR=$RANDOM%100
            let CHUNK_NUMBER=$MEDIA_SEQ_NUM+$CHUNK_ADDED
            echo -e "#EXTINF:$CHUNK_PLAY_TIME_FACTOR$RANDOM_FACTOR"  >> $MANIFEST_STAGE_FILE
            echo -e "tsChunk$CHUNK_NUMBER.ts" >> $MANIFEST_STAGE_FILE
            echo "`date`: Created  Additional file tsChunk$CHUNK_NUMBER.ts " | tee -a $LOG_FILE
            let CHUNK_ADDED=$CHUNK_ADDED+1
            let x=$x-1
        done
    fi

    # Now we have created a temp file for our m3u8
    # Let's create all the chunk files required
    for file in `grep tsChunk $MANIFEST_STAGE_FILE` ; do

        # If http error status file is available, do not create some of the files
        if [ -f $HTTP_4XX_STATUS_FILE ] ; then

            if [ -f /tmp/$file.4xx ] ; then
                # We have decided not to create this file in a ealier loop,
                # so go back
                echo "`date`: File /tmp/$file.4xx  exists.. so won't create $file.." | tee -a $LOG_FILE
                continue;
            fi

            let x=$RANDOM%3
            if [ $x -gt 1 ]; then
               echo "`date`: $file was not created .. expect an http 404 error" | tee -a $LOG_FILE

               # Remove that file, it that was created in  an earlier loop
               rm -f $file
               # Create a status file to indicate that this file should not be created again , otherwise
               # in the next loop this file will be created again
               touch /tmp/$file.4xx
               continue;
            fi
        fi

        # If chunk delay status file is available, create a huge file so that
        # the download time will be affected (This is kludge, not a proper way to do)
        if [ -f $CHUNK_DELAY_STATUS_FILE ] ; then

            if [ -f /tmp/$file.chunksize ]; then
                # We have already created this file in earlier loop, so go back
                continue;
            fi

            let x=$RANDOM%3
            if [ $x -gt 1 ]; then
               echo "`date`: $file was created with bigger size.. " | tee -a $LOG_FILE
               # Remove that file, it that was created in  an earlier loop
               rm -f $file
               cat /boot/vmlinuz* >> $file

               # We should not create this file in the next loop, with the
               # default size, so create a status file to avoid that.
               touch /tmp/$file.chunksize
               continue;
            fi
        fi
        echo "`date`: Created file ... $file" | tee -a $LOG_FILE
        cp sample.ts $file
    done

    # Move the staging file to test.m3u8
    cp $MANIFEST_STAGE_FILE test.m3u8

    # For the next manifest file, the sequence number will be increased
    let OLD_MEDIA_SEQ_NO=MEDIA_SEQ_NUM
    let MEDIA_SEQ_NUM=$MEDIA_SEQ_NUM+1

    #Sleep until we need to update the manifest file
    sleep $MANIFEST_GEN_DELAY_TIME

    # Let's delete the tschunk which will not be referenced in the next manifest..
    # to save our space in EC2 instance
    rm -f tsChunk$OLD_MEDIA_SEQ_NO.ts

done
