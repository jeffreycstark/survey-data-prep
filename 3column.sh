for f in *.txt; do
    printf '\n===== %s =====\n\n' "$f"
    cat "$f"
done | pr -3 -t | lp
