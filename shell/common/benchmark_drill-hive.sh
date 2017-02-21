# Benchmark based on Pavlo's benchmark and HiveBench hivebench implementation
source_file "$ALOJA_REPO_PATH/shell/common/common_hive.sh"
set_hive_requires
source_file "$ALOJA_REPO_PATH/shell/common/common_drill.sh"
set_drill_requires

BENCH_REQUIRED_FILES["hivebench"]="$ALOJA_PUBLIC_HTTP/aplic2/tarballs/hivebench.tar.gz"

#BENCH_REQUIRED_FILES["tpch-hive"]="$ALOJA_PUBLIC_HTTP/aplic2/tarballs/tpch-hive.tar.gz"
[ ! "$BENCH_LIST" ] && BENCH_LIST="datagen aggregation test"

data_location="/hivebench/data"
hivebench_pages="1200" #hivebench default 120000000
hivebench_visits="10000" #hivebench default 1000000000

#[ "$(get_hadoop_major_version)" != "2" ] && die "Hadoop v2 is required for TPCH-hive"


benchmark_suite_config() {

  initialize_hadoop_vars
  prepare_hadoop_config "$NET" "$DISK" "$BENCH_SUITE"
  start_hadoop

  initialize_hive_vars
  prepare_hive_config "$HIVE_SETTINGS_FILE" "$HIVE_SETTINGS_FILE_PATH"

  initialize_drill_vars
  prepare_drill_config "$NET" "$DISK" "$BENCH_SUITE"

}

# Iterate the specified benchmarks in the suite
benchmark_suite_run() {
  logger "INFO: Running $BENCH_SUITE"

  for bench in $BENCH_LIST ; do

    # Prepare run (in case defined)
    function_call "benchmark_prepare_$bench"

    # Bench Run
    function_call "benchmark_$bench"

    # Validate (eg. teravalidate)
    function_call "benchmark_validate_$bench"

    # Clean-up HDFS space (in case necessary)
    clean_HDFS "$bench_name" "$BENCH_SUITE"

  done

  logger "INFO: DONE executing $BENCH_SUITE"
}

benchmark_suite_save() {
  logger "DEBUG: No specific ${FUNCNAME[0]} defined for $BENCH_SUITE"
}

benchmark_suite_cleanup() {
  clean_hadoop
  logger "INFO: Stopping HiveServer2"
  # kill hiveserver2 since there is no command to stop it...
  kill -9 $(ps aux | grep '[S]erver2' | awk '{print $2}')
  #stops metastore
  kill -9 $(lsof -t -i:9083)


}

benchmark_datagen() {
  local bench_name="${FUNCNAME[0]##*benchmark_}"
  logger "INFO: Running $bench_name"

  if [ "$DELETE_HDFS" ] ; then
    local jar="$(get_local_apps_path)/hivebench/datatools.jar"
    execute_hadoop_new "$bench_name" "jar $jar HiBench.DataGen -t hive -m $MAX_MAPS -r $MAX_MAPS -b $(dirname "$data_location") -n $(basename "$data_location") -p $hivebench_pages -v $hivebench_visits -o sequence" "time"
  else
    logger "WARNING: Reusing data already generated"
  fi
}

benchmark_prepare_aggregation() {
  local bench_name="${FUNCNAME[0]##*benchmark_}"
  logger "INFO: Running $bench_name"

  local create_tables="
DROP TABLE uservisits;
CREATE EXTERNAL TABLE uservisits (sourceIP STRING,destURL STRING,visitDate STRING,adRevenue DOUBLE,userAgent STRING,countryCode STRING,languageCode STRING,searchWord STRING,duration INT ) ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' STORED AS SEQUENCEFILE LOCATION '$data_location/uservisits';
DROP TABLE uservisits_aggre;
"

  local local_file_path="$(create_local_file "$bench_name.sql" "$create_tables")"

  logger "DEBUG: Running query:\n$create_tables"
  execute_hive "$bench_name" "-f '$local_file_path'" "time"
}

benchmark_aggregation() {
  local bench_name="${FUNCNAME[0]##*benchmark_}"
  logger "INFO: Running $bench_name"

  local create_tables="
CREATE TABLE uservisits_aggre ( sourceIP STRING, sumAdRevenue DOUBLE) STORED AS SEQUENCEFILE ;
INSERT OVERWRITE TABLE uservisits_aggre SELECT sourceIP, SUM(adRevenue) FROM uservisits GROUP BY sourceIP;
"

  local local_file_path="$(create_local_file "$bench_name.sql" "$create_tables")"

  logger "DEBUG: Running query:\n$create_tables"
  execute_hive "$bench_name" "-f '$local_file_path'" "time"
}

benchmark_prepare_test(){

  # Copy hive-site.xml to hive conf folder (thrift server)
  cp $(get_base_configs_path)/hive1_conf_template/hive-site.xml $(get_local_apps_path)/apache-hive-1.2.1-bin/conf/
  logger "INFO: Starting metastore server"
  #execute_cmd_master "$bench_name" "$(get_hive_exports) $HIVE_HOME/bin/hive --service hiveserver2 &&"
  logger "INFO: Executing with hive"
  local hive_exports="$(get_hive_exports)"
  local hive_bin="$HIVE_HOME/bin/hive"
  local hive_cmd="$hive_exports
  $hive_bin --service metastore &"
  eval $hive_cmd
  logger "INFO: Wait 120 seconds to get server started..."
  sleep 120



}

benchmark_test(){

  local bench_name="${FUNCNAME[0]##*benchmark_}"
  logger "INFO: Running $bench_name"
  start_drill
  local show_databases="show databases;
  select * from hive.uservisits limit 5;
  "
  local local_file_path="$(create_local_file "$bench_name.sql" "$show_databases")"
  #currently no sql file or sql statement, opens up drill shell to enter them manually for testing purposes
  execute_drill "$bench_name" "" "time"

}
