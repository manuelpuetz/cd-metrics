curl \
-H "Authorization: Bearer `cat ~/.flyrc | grep "team: nh" -A 3 | grep -E $'value( .*)?' | awk '{print $2}'`" \
$1
