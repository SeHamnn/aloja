#!/usr/bin/env bash
#DRILL SPECIFIC FUNCTIONS
source_file "$ALOJA_REPO_PATH/shell/common/common_hadoop.sh"
set_hadoop_requires

get_drill_config_folder() {
  local config_folder_name

  if [ "$DRILL_CUSTOM_CONFIG" ] ; then
    config_folder_name="$DRILL_CUSTOM_CONFIG"
  else
    config_folder_name="drill_1.6_conf_template"
  fi

  echo -e "$config_folder_name"
}



# Sets the required files to download/copy
# TODO : Setup own mirror for Drill
set_drill_requires() {

  [ ! "$DRILL_VERSION" ] && die "No DRILL_VERSION specified"
  BENCH_REQUIRED_FILES["$DRILL_VERSION"]="http://apache.lauf-forum.at/drill/drill-1.8.0/$DRILL_VERSION.tar.gz"

  #also set the config here
  BENCH_CONFIG_FOLDERS="$BENCH_CONFIG_FOLDERS drill_1.6_conf_template"

}


# Helper to print a line with required exports
get_drill_exports() {
  local to_export

  to_export="$(get_hadoop_exports)
export DRILL_VERSION='$DRILL_VERSION';
export DRILL_HOME='$(get_local_apps_path)/${DRILL_VERSION}';
export DRILL_CONF_DIR=$(get_local_apps_path)/${DRILL_VERSION}/conf;
export DRILL_LOG_DIR=$(get_local_bench_path)/${DRILL_VERSION}/bin;
"

  echo -e "$to_export\n"
}


#old code moved here
# TODO cleanup
initialize_drill_vars() {

   BENCH_CONFIG_FOLDERS="$BENCH_CONFIG_FOLDERS drill_1.6_conf_template"

  if [ "$clusterType" == "PaaS" ]; then
    DRILL_HOME="/usr/bin/drill"
    DRILL_CONF_DIR="/etc/drill/conf"
  else
     [ ! "$HDD" ] && die "HDD var not set!"

     BENCH_DRILL_DIR="$(get_local_apps_path)/$DRILL_VERSION" #execution dir

     DRILL_CONF_DIR="$HDD/drill_conf"
     DRILL_EXPORTS="$(get_drill_exports)"

     if [ ! "$BENCH_LEAVE_SERVICES" ] ; then
       #make sure all spawned background jobs and services are stoped or killed when done
       if [ "$INSTRUMENTATION" == "1" ] ; then
         update_traps "stop_drill;" "update_logger"
       else
         update_traps "stop_drill;" "update_logger"
       fi
     else
       update_traps "echo 'WARNING: leaving services running as requested (stop manually).';"
     fi
  fi
}



prepare_drill_config(){

 if [ "$clusterType" == "PaaS" ]; then
  # Save config
  logger "INFO: Saving bench spefic config to job folder"
  for node in $node_names ; do
    ssh "$node" "
    mkdir -p $JOB_PATH/conf_$node;
    cp $DRILL_CONF_DIR/* $JOB_PATH/conf_$node/" &
  done
 else
  logger "INFO: Preparing drill run specific config"
  $DSH "mkdir -p $HDD/drill_conf; cp -r $(get_local_configs_path)/$(get_drill_config_folder)/* $(get_local_apps_path)/${DRILL_VERSION}/conf;"

  # Set correct permissions for instrumentation's sniffer
  [ "$INSTRUMENTATION" == "1" ] && instrumentation_set_perms
 fi
}



# Just an alias
start_drill() {
  restart_drill
}

#TODO DO REAL CHECK IF DRILLBIT IS READY (LIKE IN HADOOP FOR HDFS)
restart_drill(){
  if [ "$clusterType" != "PaaS" ]; then
    logger "INFO: Restart DRILL"
    #just in case stop all first
    stop_drill
    #$DSH "/scratch/local/aloja-bench_3/apache-drill-1.8.0/bin/drillbit.sh start"
    $DSH "$DRILL_EXPORTS $BENCH_DRILL_DIR/bin/drillbit.sh start"
    logger "INFO: Drill ready"
  fi
}


# Stops drill and checks for open ports
# $1 retry (to prevent recursion)
stop_drill(){
  local dont_retry="$1"

  if [ "$clusterType=" != "PaaS" ] ; then
    if [ ! "$dont_retry" ] ; then
      logger "INFO: Stop Drill"
    else
      logger "INFO: Stop Drill (retry)"
    fi
    $DSH "$DRILL_EXPORTS $BENCH_DRILL_DIR/bin/drillbit.sh stop"

 fi

}

# Performs the actual benchmark execution
# $1 benchmark name
# $2 command
# $3 if to time exec
execute_drill(){
  local bench="$1"
  local cmd="$2"
  local time_exec="$3"

  local drill_cmd="$(get_drill_cmd) $cmd"
  #caused benchmark not to start, probably not enough ressources (have to test outside VMs)
  # TODO Check if monitor works on real cluster
  # Start metrics monitor (if needed)
#  if [ "$time_exec" ] ; then
#    save_disk_usage "BEFORE"
#    restart_monit
#    set_bench_start "$bench"
#  fi

  logger "DEBUG: DRILL command:\n$drill_cmd"

  # was needed for ZK
  # TODO Check if still necessary
  export JAVA_HOME="$(get_java_home)"

  # starting ZK outside causes ZK not to launch properly - drillbits don't manage to get a connection
  #start_zookeeper
  #logger "INFO: Wait 120 seconds to get server started..."
  #sleep 120

  # Checking the log files of all drillbits - used to debug
  #$DSH "cat $BENCH_DRILL_DIR/log/drillbit.out"

  #Checking the config files - used to debug
  #$DSH "cat $BENCH_DRILL_DIR/conf/drill-override.conf"

  #Just a simple Check if drillbits are ready
  $DSH "$DRILL_EXPORTS $BENCH_DRILL_DIR/bin/drillbit.sh status"

  #curl http://localhost:8047/storage/hive.json

  #need to set hive plugin here, sometimes causes the benchmark not to finish
  #set_hive_plugin
  #curl -X POST -H "Content-Type: application/json" -d '{"name":"hive", "config": {"type": "hive", "enabled": true,"configProps": {"hive.metastore.uris": "thrift://vagrant-99-00:9083","hive.metastore.warehouse.dir": "/tmp/drill_hive_wh","hive.metastore.sasl.enabled": "false"}}}' http://localhost:8047/storage/hive.json


  # Run the command and time it
  time_cmd_master "$drill_cmd" "$time_exec"

  # Stop metrics monitors and save bench (if needed)
  if [ "$time_exec" ] ; then
    #set_bench_end "$bench"
    #stop_monit
    #save_disk_usage "AFTER"
    save_drill "$bench"
  fi
}

# Returns the the path to the drill binary with the proper exports
get_drill_cmd() {
  local drill_exports
  local drill_cmd
  export JAVA_HOME="$(get_java_home)"

  drill_exports="$(get_drill_exports)"

  #currently hardcoded for the ZK that launches on main node
  #the zk is defined in the config file drill-override
  drill_cmd="$drill_exports\n$(get_local_apps_path)/${DRILL_VERSION}/bin/drill-conf "
  echo -e "$drill_cmd"
}

# $1 bench name
save_drill() {
  local bench_name="$1"
  logger "WARNING: missing to implement a proper save_drill()"
  #stop_drill
  #save_zookeeper
  save_hadoop "$bench_name"
  }

  #set hive plugin for drill with REST api
set_hive_plugin(){
  curl -X POST -H "Content-Type: application/json" -d '{"name":"hive", "config": {"type": "hive", "enabled": true,"configProps": {"hive.metastore.uris": "thrift://vagrant-99-00:9083","hive.metastore.warehouse.dir": "/tmp/drill_hive_wh","hive.metastore.sasl.enabled": "false"}}}' http://localhost:8047/storage/hive.json

}
