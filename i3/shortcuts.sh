#!/bin/sh
# Renders the keybindings from the live i3 config in a searchable rofi list.

config=${1:-${XDG_CONFIG_HOME:-$HOME/.config}/i3/config}
[ -r "$config" ] || {
	notify-send -a i3 "i3 shortcuts" "cannot read $config"
	exit 1
}

awk '
# Substitutes i3 set-variables; the token scan takes the longest name, so
# $ws10 never resolves as $ws1 followed by a literal 0.
function expand(s,   out, name, val) {
	out = ""
	while (match(s, /\$[A-Za-z_][A-Za-z0-9_]*/)) {
		name = substr(s, RSTART, RLENGTH)
		val = (name in var) ? var[name] : name
		out = out substr(s, 1, RSTART - 1) val
		s = substr(s, RSTART + RLENGTH)
	}
	return out s
}

function unquote(s,   q) {
	q = substr(s, 1, 1)
	if ((q == "\"" || q == "'\''") && length(s) > 1 && substr(s, length(s)) == q)
		s = substr(s, 2, length(s) - 2)
	return s
}

function prettykeys(s,   n, i, parts, out, k, low) {
	n = split(s, parts, "+")
	out = ""
	for (i = 1; i <= n; i++) {
		k = parts[i]
		low = tolower(k)
		if (low == "mod4") k = "Super"
		else if (low == "mod1") k = "Alt"
		else if (low == "control" || low == "ctrl") k = "Ctrl"
		else if (low == "shift") k = "Shift"
		out = (i == 1) ? k : out "+" k
	}
	return out
}

/^[[:space:]]*set[[:space:]]+\$/ {
	var[$2] = unquote($3)
	next
}

/^[[:space:]]*mode[[:space:]]+[^{]+\{/ {
	line = expand($0)
	sub(/^[[:space:]]*mode[[:space:]]+/, "", line)
	sub(/[[:space:]]*\{.*$/, "", line)
	mode = unquote(line)
	next
}

/^[[:space:]]*\}/ { mode = ""; next }

/^[[:space:]]*bind(sym|code)[[:space:]]/ {
	line = expand($0)
	sub(/^[[:space:]]*/, "", line)
	n = split(line, f, /[[:space:]]+/)

	i = 2
	while (i <= n && f[i] ~ /^--/) i++   # skip --release, --whole-window, ...
	if (i > n) next

	keys = prettykeys(f[i])
	action = ""
	for (i++; i <= n; i++) action = (action == "") ? f[i] : action " " f[i]

	sub(/^exec[[:space:]]+--no-startup-id[[:space:]]+/, "", action)
	sub(/^exec[[:space:]]+/, "", action)
	action = unquote(action)
	if (length(action) > 90) action = substr(action, 1, 87) "..."

	if (mode != "") keys = "[" mode "] " keys
	printf "%-30s %s\n", keys, action
}
' "$config" | rofi -dmenu -i -no-custom -p shortcuts \
	-mesg "i3 keybindings from ${config#$HOME/} — type to filter, Esc to close" \
	-theme-str '
		window { width: 60%; }
		listview { lines: 22; }
		element-icon { enabled: false; }
		* { font: "monospace 10"; }
	' >/dev/null
