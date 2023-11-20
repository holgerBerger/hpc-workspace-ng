dub test --config ws_list
echo
echo
dub test --config ws_expirer -- -t 1
echo
echo
dub test --config ws_allocate
