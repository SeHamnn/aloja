# Benchmark to test Hive installation and configurations
source_file "$ALOJA_REPO_PATH/shell/common/common_drill.sh"
set_drill_requires

#BENCH_REQUIRED_FILES["tpch-hive"]="$ALOJA_PUBLIC_HTTP/aplic2/tarballs/tpch-hive.tar.gz"
[ ! "$BENCH_LIST" ] && BENCH_LIST="drill-test drillm"

# Implement only the different functionality

benchmark_suite_config() {
  initialize_hadoop_vars
  prepare_hadoop_config "$NET" "$DISK" "$BENCH_SUITE"
  start_hadoop

  initialize_drill_vars
  prepare_drill_config "$NET" "$DISK" "$BENCH_SUITE"
  start_drill
}

benchmark_suite_cleanup() {
  clean_hadoop
}


benchmark_drill-test() {
  local bench_name="${FUNCNAME[0]##*benchmark_}"
  logger "INFO: Running $bench_name"
  
  start_zookeeper
  logger "INFO: Wait 120 seconds to get zookeeper started..."
  sleep 120
  local show_databases="SELECT 'value' from sys.version;
  "
  local VARIABLE="test"
  local local_file_path="$(create_local_file "$bench_name.sql" "$show_databases")"
  #simple test query to see if connection is established
  execute_drill "$bench_name" "-f '$local_file_path'" "time"
  
}

benchmark_drillm() {
  local bench_name="${FUNCNAME[0]##*benchmark_}"
  local show_databases="show databases;
  "
  local VARIABLE="test"
  local local_file_path="$(create_local_file "$bench_name.sql" "$show_databases")"
  #simple test query to see if connection is established
  execute_drill "$bench_name" "-f '$local_file_path'" "time"
}