_query-select() {
	local table="$1"
	local where="${2:-1}"

	_query -box <<< "SELECT * FROM $table WHERE $where"
}


_query-insert() {
	local table="$1"
	local columns=""
	local values=""
	local notnull

	for name in $(_query <<< "PRAGMA table_info($table);" | awk -F "|" '{print $2}'); do
		notnull=$(_query <<< "SELECT \"notnull\" FROM pragma_table_info('$table') WHERE name='$name';")
		if [ "$columns" != "" ]; then columns="$columns,"; fi;
		if [ "$values" != "" ]; then values="$values,"; fi;

		read -p "$name: " val_$name;
		value="val_${name}"
		columns="$columns $name"
		if ! [ "${!value}" ] && [ "$notnull" -eq 0 ]; then
			values="$values NULL"
		else
			values="$values '${!value}'"
		fi
	done

	_query <<< "PRAGMA foreign_keys=ON; BEGIN; INSERT INTO $table($columns) VALUES($values); COMMIT;"
}

_query-add() {
	_query-insert "$@"
}

_sql_in() {
	local ret=""
	for r in "$@"; do
		ret="${ret:+$ret,}'$r'"
	done
	echo "$ret"
}
