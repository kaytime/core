for entry in /layouts/*.sh; do
    if [ "$entry" != "main.sh" ]; then
        source /layouts/$entry
    fi
done
