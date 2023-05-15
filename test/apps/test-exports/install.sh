echo "project_var=$project_var"
echo "each_app_var=$each_app_var"
echo "from_build_file=$from_build_file"
echo "some_array:"
for f in "${some_array[@]}"; do
	echo " - $f";
done;
