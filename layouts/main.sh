for entry in /layouts/*.sh; do
    if [ "$entry" != "main.sh" ]; then
        source $entry
    fi
done
