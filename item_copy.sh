#!/bin/bash
#RUN AS bash test.sh <src_region> <src_env> <dest_region> <dest_env> <table1> <table2> <table3>
#eg-: bash test.sh us-west-1 UAT us-west-1 STG  TableOne TableTwo
#it will COPY FROM TableOneDEV TO TableOneUAT
#it will COPY FROM TableTwoDEV TO TableTwoUAT

# array passed as first argument
arr=("$@")
count=${#arr[*]}

source_region=${arr[0]}
source_env=${arr[1]}
destination_region=${arr[2]}
destination_env=${arr[3]}

function split_put {
    # The number of files to split into
    TABLE_FROM=$1 
    TABLE_TO=$2
    echo $TABLE_FROM $TABLE_TO  

    #get all items
    aws dynamodb scan --region  $source_region --table-name "$TABLE_FROM" --output json | jq '.Items' > items.json

    # The input JSON file
    input_file="items.json"    
    # The number of items per file
    item_count=$(jq length $input_file)    

    for ((j=0; j<$item_count; j+=25)) do
      start=$j
      end=$((j + 25))
      if [[ $end -ge $item_count ]]
      then
          end=$item_count
          # Extract the portion of the input file for this iteration
          jq --arg s "$start" --arg e "$end"  '.[$s|tonumber:$e|tonumber]' $input_file | jq "{ \"$TABLE_TO\": [ .[] | { PutRequest: { Item: . } } ] }"  > "output-$j.json"

          #write
          aws dynamodb batch-write-item --request-items file://"output-$j.json" --region  $destination_region

          #remove
          rm output-$j.json
      else
          # Extract the portion of the input file for this iteration
          jq --arg s "$start" --arg e "$end"  '.[$s|tonumber:$e|tonumber]' $input_file | jq "{ \"$TABLE_TO\": [ .[] | { PutRequest: { Item: . } } ] }"  > "output-$j.json"

          #write
          aws dynamodb batch-write-item --request-items file://"output-$j.json" --region  $destination_region
          
          #remove
          rm output-$j.json
      fi      
    done
    rm $input_file
}

# iterate through array and print index and value
for ((i=4; i<$count; i++)); do
    echo "For ${arr[i]}"
    # tables
    TABLE_FROM=${arr[i]}${source_env}
    TABLE_TO=${arr[i]}${destination_env}
    check_count=$(aws dynamodb scan --region  $source_region --table-name "$TABLE_FROM" --output json | jq '.Items' |  jq length)

    if [[ $check_count -eq 0 ]]
    then
        echo "the table $TABLE_FROM is empty"
        continue
    fi 
    if [[ $check_count -gt 25 ]]
    then
        split_put "$TABLE_FROM" "$TABLE_TO"
    fi    
    if [[ $check_count -le 25 ]]
    then
        # read
        aws dynamodb scan --region  $source_region \
          --table-name "$TABLE_FROM" \
          --output json \
         | jq "{ \"$TABLE_TO\": [ .Items[] | { PutRequest: { Item: . } } ] }" \
         > "$TABLE_TO-file.json"  
         
        # write
        aws dynamodb batch-write-item --request-items file://"$TABLE_TO-file.json" --region  $destination_region

        # clean up
        rm "$TABLE_TO-file.json"
    fi
done
