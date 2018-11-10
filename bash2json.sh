# this is the test array used to test the function \
test_array=( zero one two three four five six ); \
# this function turns a bash array into valid json \
Print_array_as_json() { \
  # first, we store the name of the requested array as $1 \
  requested_array="${1}"; \
  # this grabs the number of elements in the requested array \
  elements_in_requested_array="$(eval echo \${\#${requested_array}[@]})"; \
  # init our array_element_index counter at 0 \
  array_element_index="0"; \
  # init our array_element_count counter at 1 \
  array_element_count="$((${array_element_index}+1))"; \
  # printf our first part of valid json, this is the object/array name \
  printf "{\n  \"${requested_array}\" :  [\n"; \
  # this loops through the elements, printing each one with valid json delimiters \
  for array_element in $(eval echo \${${requested_array}[@]}); do \
    printf "    {\n"; \
    printf "      \"array_element_${array_element_index}\" : \"${array_element}\"\n"; \
    # this part checks to see if its the last element; last one gets no "," after \
    if [ "${array_element_count}" -ne "${elements_in_requested_array}" ]; then \
      printf "    },\n"; \
    else \
      printf "    }\n"; \
    fi; \
    # we need to increment our counters at the end of the loop
    ((array_element_index++)); \
    ((array_element_count++)); \
  done; \
  # closes out the json object
  printf "  ]\n}\n"; \
}; \
# now that the function is defined, lets run it, and pass test_array as $1 \
# jq is a utility to "pretty print" valid json; using it to test the function \
Print_array_as_json test_array | jq '.'



Print_file_as_json() { \
  line_count=0; \
  total_lines=$(cat ${1} | wc -l); \
  printf "{ \"${1//\//\\/}\" : \n  [\n"; \
  while read -r line; do \
    if [ "$((${line_count}+1))" -ne "${total_lines}" ]; then \
      python -c \
      "import sys,json; \
        print \
        '    { \"line_$((${line_count}+1))\" : ' \
        + json.dumps(sys.stdin.read()) \
        + \" }, \" \
      " \
      2>/dev/null <<<${line} || \
      python -c \
      "import sys; \
      import simplejson as json; \
        print \
        '    { \"line_$((${line_count}+1))\" : ' \
        + json.dumps(sys.stdin.read()) \
        + \" } \" \
      " \
      2>/dev/null <<<${line} \
    else \
      python -c \
      "import sys,json; \
        print \
        '    { \"line_$((${line_count}+1))\" : ' \
        + json.dumps(sys.stdin.read()) \
        + \" } \" \
      " \
      2>/dev/null <<<${line} || \
      python -c \
      "import sys; \
        import simplejson as json; \
        print \
        '    { \"line_$((${line_count}+1))\" : ' \
        + json.dumps(sys.stdin.read()) \
        + \" } \" \
      " \
      2>/dev/null <<<${line} \
    fi; \
    ((line_count++)); \
  done < ${1}; \
  printf "  ]\n}\n"; \
}; \
Print_file_as_json /etc/passwd | jq '.'
