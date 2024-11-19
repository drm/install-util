_query-select() {
	local table="$1"
	local where="${2:-1}"

	_query -box <<< "SELECT * FROM $table WHERE $where"
}


_query-insert() {
	local table="$1"
	local columns=""
	local values=""

	for name in $(_query <<< "PRAGMA table_info($table);" | awk -F "|" '{print $2}'); do
		if [ "$columns" != "" ]; then columns="$columns,"; fi;
		if [ "$values" != "" ]; then values="$values,"; fi;
		
		read -p "$name: " val_$name;
		value="val_${name}"
		columns="$columns $name"
		values="$values '${!value}'"
	done

	_query <<< "PRAGMA foreign_keys=ON; INSERT INTO $table($columns) VALUES($values);"
}

_query-add() {
	_query-insert "$@"
}
