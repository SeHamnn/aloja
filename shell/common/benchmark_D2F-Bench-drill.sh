# TPC-H benchmark from Todor Ivanov https://github.com/t-ivanov/D2F-Bench/
# Hive version
# Benchmark to test Hive installation and configurations

source_file "$ALOJA_REPO_PATH/shell/common/common_TPC-H.sh"
source_file "$ALOJA_REPO_PATH/shell/common/common_drill.sh"
set_drill_requires


benchmark_suite_run() {
  logger "INFO: Running $BENCH_SUITE"
  initialize_drill_vars
  prepare_drill_config "$NET" "$DISK" "$BENCH_SUITE"
  
  tpc-h_datagen

  benchmark_prepare_drill

  BENCH_CURRENT_NUM_RUN="1" #reset the global counter

  # Iterate at least one time
  while true; do
    [ "$BENCH_NUM_RUNS" ] && logger "INFO: Starting iteration $BENCH_CURRENT_NUM_RUN of $BENCH_NUM_RUNS"

    for query in $BENCH_LIST ; do
      logger "INFO: RUNNING $query of $BENCH_NUM_RUNS runs"
      execute_query_drill "$query"
    done

    # Check if requested to iterate multiple times
    if [ ! "$BENCH_NUM_RUNS" ] || [[ "$BENCH_CURRENT_NUM_RUN" -ge "$BENCH_NUM_RUNS" ]] ; then
      break
    else
      BENCH_CURRENT_NUM_RUN="$((BENCH_CURRENT_NUM_RUN + 1))"
    fi
  done

  logger "INFO: DONE executing $BENCH_SUITE"
}




# $1 query number
execute_query_drill() {
  local query="$1"
  sed -i s/DATABASE/hive.$TPCH_DB_NAME/g $D2F_local_dir/tpch/queries/drill/$query.sql
  execute_drill "$query" "--force=true -f $D2F_local_dir/tpch/queries/drill/$query.sql" "time"
  sed -i s/hive.$TPCH_DB_NAME/DATABASE/g $D2F_local_dir/tpch/queries/drill/$query.sql
}

benchmark_prepare_drill(){

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
  start_drill
  start_zookeeper
  logger "INFO: Wait 120 seconds to get zookeeper started..."
  sleep 120
  set_hive_plugin
}


benchmark_drilling(){

  local bench_name="${FUNCNAME[0]##*benchmark_}"
  logger "INFO: Running $bench_name"
  start_drill
  #local show_databases="use hive.tpch_bin_flat_orc_1;
  #select * from nation limit 5;
  #"
  local show_databases="show databases;
use dfs.tmp;
drop table if exists q2_minimum_cost_supplier_tmp1;
create table q2_minimum_cost_supplier_tmp1 (s_acctbal, s_name, n_name, p_partkey, ps_supplycost, p_mfgr, s_address, s_phone, s_comment) as 
select 
  s.s_acctbal, 
  s.s_name, 
  n.n_name, 
  p.p_partkey, 
  ps.ps_supplycost, 
  p.p_mfgr, 
  s.s_address, 
  s.s_phone, 
  s.s_comment 
from 
  hive.tpch_orc_1.nation n join hive.tpch_orc_1.region r 
  on 
    n.n_regionkey = r.r_regionkey and r.r_name = 'EUROPE' 
  join hive.tpch_orc_1.supplier s 
  on 
s.s_nationkey = n.n_nationkey 
  join hive.tpch_orc_1.partsupp ps 
  on  
s.s_suppkey = ps.ps_suppkey 
  join hive.tpch_orc_1.part p 
  on 
    p.p_partkey = ps.ps_partkey 
and 
p.p_size = 37 and p.p_type like '%COPPER' ;

drop table if exists q2_minimum_cost_supplier_tmp2;
create table q2_minimum_cost_supplier_tmp2 (p_partkey, ps_min_supplycost) as 
select 
  p_partkey, min(ps_supplycost) 
from  
  q2_minimum_cost_supplier_tmp1 
group by p_partkey;



drop table if exists q2_minimum_cost_supplier;
create table q2_minimum_cost_supplier (s_acctbal, s_name, n_name , p_partkey, p_mfgr, s_address, s_phone, s_comment) as
select 
  t1.s_acctbal, 
  t1.s_name, 
  t1.n_name, 
  t1.p_partkey, 
  t1.p_mfgr, 
  t1.s_address, 
  t1.s_phone, 
  t1.s_comment 
from 
  q2_minimum_cost_supplier_tmp1 t1 join q2_minimum_cost_supplier_tmp2 t2 
on 
  t1.p_partkey = t2.p_partkey 
and 
t1.ps_supplycost=t2.ps_min_supplycost 
order by 
s_acctbal desc, n_name, s_name, p_partkey 
limit 100;



select * from q2_minimum_cost_supplier limit 5;
  "
  local local_file_path="$(create_local_file "$bench_name.sql" "$show_databases")"
  #currently no sql file or sql statement, opens up drill shell to enter them manually for testing purposes
  execute_drill "$bench_name" "-f '$local_file_path'" "time"
}


benchmark_suite_cleanup() {
  clean_hadoop
  logger "INFO: Stopping HiveServer2"
  # kill hiveserver2 since there is no command to stop it...
  kill -9 $(ps aux | grep '[S]erver2' | awk '{print $2}')
  #stops metastore
  kill -9 $(lsof -t -i:9083)

}