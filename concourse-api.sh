curl \
-H "Authorization: Bearer `cat ~/.flyrc | grep "team: ${1}" -A 3 | grep -E $'value( .*)?' | awk '{print $2}'`" \
$2
