#!/bin/sh
# Renders the keybindings from the live i3 config in a searchable rofi list.

config=${1:-${XDG_CONFIG_HOME:-$HOME/.config}/i3/config}
[ -r "$config" ] || {
	notify-send -a i3 "i3 shortcuts" "cannot read $config"
	exit 1
}

# Keys whose function is already printed on the keycap. Extended regex, matched
# against the unexpanded key spec.
skip='^XF86'

awk -v skip="$skip" '
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
	sym["question"] = "?"; sym["semicolon"] = ";"; sym["comma"] = ","
	sym["period"] = "."; sym["slash"] = "/"; sym["backslash"] = "\\"
	sym["minus"] = "-"; sym["equal"] = "="; sym["apostrophe"] = "'\''"
	sym["bracketleft"] = "["; sym["bracketright"] = "]"; sym["grave"] = "`"

	n = split(s, parts, "+")
	out = ""
	for (i = 1; i <= n; i++) {
		k = parts[i]
		low = tolower(k)
		if (low == "mod4") k = "Super"
		else if (low == "mod1") k = "Alt"
		else if (low == "control" || low == "ctrl") k = "Ctrl"
		else if (low == "shift") k = "Shift"
		else if (low in sym) k = sym[low]
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
	if (skip != "" && f[i] ~ skip) next

	keys = prettykeys(f[i])
	action = ""
	for (i++; i <= n; i++) action = (action == "") ? f[i] : action " " f[i]

	sub(/^exec[[:space:]]+--no-startup-id[[:space:]]+/, "", action)
	sub(/^exec[[:space:]]+/, "", action)
	action = unquote(action)
	if (length(action) > 90) action = substr(action, 1, 87) "..."

	if (mode != "") keys = "[" mode "] " keys

	# Buffered rather than printed, so END can fold digit-indexed runs.
	rows++
	K[rows] = keys
	A[rows] = action
	sigA[rows] = generalise(action)
	# A trailing single digit is the only thing allowed to vary within a run.
	last = substr(keys, length(keys))
	prev = (length(keys) > 1) ? substr(keys, length(keys) - 1, 1) : ""
	if (last ~ /[0-9]/ && prev !~ /[0-9]/) {
		P[rows] = substr(keys, 1, length(keys) - 1)
		D[rows] = last
	} else
		P[rows] = ""
}

function generalise(s) {
	gsub(/[0-9]+/, "#", s)
	return s
}

# True when the run i..j covers an unbroken span of the number row, so the
# folded "1..0" cannot advertise a digit that is not actually bound.
function contiguous(i, j,   d, ds) {
	ds = ""
	for (d = i; d <= j; d++) ds = ds D[d]
	return index("1234567890", ds) > 0
}

END {
	for (i = 1; i <= rows; i++) {
		j = i
		while (P[i] != "" && j < rows && P[j + 1] == P[i] && sigA[j + 1] == sigA[i])
			j++
		while (j > i && !contiguous(i, j)) j--

		if (j - i + 1 >= 3) {
			folded = A[i]
			gsub(/[0-9]+/, "N", folded)
			printf "%-30s %s\n", P[i] D[i] ".." D[j], folded
			i = j
		} else
			printf "%-30s %s\n", K[i], A[i]
	}
}
' "$config" | rofi -dmenu -i -no-custom -p shortcuts \
	-mesg "i3 keybindings from ${config#$HOME/} — type to filter, Esc to close" \
	-theme-str '
		window { width: 60%; }
		listview { lines: 22; }
		element-icon { enabled: false; }
		* { font: "monospace 10"; }
	' >/dev/null
