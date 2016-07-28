#!/usr/bin/env bash
#DRILL SPECIFIC FUNCTIONS
source_file "$ALOJA_REPO_PATH/shell/common/common_hadoop.sh"
set_hadoop_requires


source_file "$ALOJA_REPO_PATH/shell/common/common_zookeeper.sh"
set_zookeeper_requires

get_drill_config_folder() {
  local config_folder_name

  if [ "$HADOOP_CUSTOM_CONFIG" ] ; then
    config_folder_name="$DRILL_CUSTOM_CONFIG"
  else
    config_folder_name="drill_1.6_conf_template"
  fi

  echo -e "$config_folder_name"
}



# Sets the required files to download/copy
set_drill_requires() {

  [ ! "$DRILL_VERSION" ] && die "No DRILL_VERSION specified"

  BENCH_REQUIRED_FILES["$DRILL_VERSION"]="http://apache.mesi.com.ar/drill/drill-1.6.0/$DRILL_VERSION.tar.gz"

  #also set the config here
  BENCH_CONFIG_FOLDERS="$BENCH_CONFIG_FOLDERS drill_1.6_conf_template"

}


# Helper to print a line with requiered exports
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

# Get the list of slaves
# TODO should be improved to include master node as worker node if necessary
# $1 list of nodes
# $2 master name
get_drill_slaves() {
  local all_nodes="$1"
  local master_name="$2"
  local only_slaves

  if [ "$all_nodes" ] && [ "$master_name" ] ; then
    only_slaves="$(echo -e "$all_nodes"|grep -v "$master_name")"
  else
    die "Empty list of nodes supplied"
  fi

  echo -e "$only_slaves"
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


# Sets the substitution values for the drill config
get_drill_substitutions() {

  #generate the path for the hadoop config files, including support for multiple volumes
  HDFS_NDIR="$(get_hadoop_conf_dir "$DISK" "dfs/name" "$PORT_PREFIX")"
  HDFS_DDIR="$(get_hadoop_conf_dir "$DISK" "dfs/data" "$PORT_PREFIX")"

  IO_MB="$((IO_FACTOR * 10))"
  MAX_REDS="$MAX_MAPS"

  cat <<EOF
s,##JAVA_HOME##,$(get_java_home),g;
s,##HADOOP_HOME##,$BENCH_HADOOP_DIR,g;
s,##JAVA_XMS##,$JAVA_XMS,g;
s,##JAVA_XMX##,$JAVA_XMX,g;
s,##JAVA_AM_XMS##,$JAVA_AM_XMS,g;
s,##JAVA_AM_XMX##,$JAVA_AM_XMX,g;
s,##LOG_DIR##,$HDD/hadoop_logs,g;
s,##REPLICATION##,$REPLICATION,g;
s,##MASTER##,$master_name,g;
s,##NAMENODE##,$master_name,g;
s,##TMP_DIR##,$HDD_TMP,g;
s,##HDFS_NDIR##,$HDFS_NDIR,g;
s,##HDFS_DDIR##,$HDFS_DDIR,g;
s,##MAX_MAPS##,$MAX_MAPS,g;
s,##MAX_REDS##,$MAX_REDS,g;
s,##IFACE##,$IFACE,g;
s,##IO_FACTOR##,$IO_FACTOR,g;
s,##IO_MB##,$IO_MB,g;
s,##PORT_PREFIX##,$PORT_PREFIX,g;
s,##IO_FILE##,$IO_FILE,g;
s,##BLOCK_SIZE##,$BLOCK_SIZE,g;
s,##PHYS_MEM##,$PHYS_MEM,g;
s,##NUM_CORES##,$NUM_CORES,g;
s,##CONTAINER_MIN_MB##,$CONTAINER_MIN_MB,g;
s,##CONTAINER_MAX_MB##,$CONTAINER_MAX_MB,g;
s,##MAPS_MB##,$MAPS_MB,g;
s,##REDUCES_MB##,$REDUCES_MB,g;
s,##AM_MB##,$AM_MB,g;
s,##BENCH_LOCAL_DIR##,$BENCH_LOCAL_DIR,g;
s,##HDD##,$HDD,g;
EOF
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
  $DSH "mkdir -p $HDD/drill_conf; cp -r $(get_local_configs_path)/$(get_drill_config_folder)/* '$HDD/drill_conf';"


  # Get the values
  subs=$(get_drill_substitutions)
  slaves="$(get_drill_slaves "$node_names" "$master_name")"
  $DSH "
$(get_perl_exports)
/usr/bin/perl -i -pe \"$subs\" $DRILL_CONF_DIR/drill-override.conf;
/usr/bin/perl -i -pe \"$subs\" $DRILL_CONF_DIR/*.xml;

echo -e '$master_name' > $DRILL_CONF_DIR/masters;
echo -e \"$slaves\" > $DRILL_CONF_DIR/slaves"


  # TODO this part need to be improved, it needs the node for multiple hostnames in a machine (eg. when IB)
  logger "INFO: Replacing per host config"
  for node in $node_names ; do
    ssh "$node" "
$export_perl
/usr/bin/perl -i -pe \"s,##HOST##,$node,g;\" $DRILL_CONF_DIR/drill-override.conf
/usr/bin/perl -i -pe \"s,##HOST##,$node,g;\" $DRILL_CONF_DIR/drill-env.sh
/usr/bin/perl -i -pe \"s,##HOST##,$node,g;\" $DRILL_CONF_DIR/logback.xml
/usr/bin/perl -i -pe \"s,##HOST##,$node,g;\" $DRILL_CONF_DIR/core-site.xml"
  done

  # Save config
  logger "INFO: Saving bench spefic config to job folder"
  for node in $node_names ; do
    ssh "$node" "
mkdir -p $JOB_PATH/conf_$node;
cp $DRILL_CONF_DIR/* $JOB_PATH/conf_$node/" &
  done

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

  # Start metrics monitor (if needed)
  if [ "$time_exec" ] ; then
    save_disk_usage "BEFORE"
    restart_monit
    set_bench_start "$bench"
  fi

  logger "DEBUG: DRILL command:\n$drill_cmd"

  export JAVA_HOME="$(get_java_home)"

  start_zookeeper
  sleep 120
  $DSH "$DRILL_EXPORTS $BENCH_DRILL_DIR/bin/drillbit.sh status"
  #ping -c30 vagrant-99-01:
  # Run the command and time it
  $(get_local_apps_path)/${DRILL_VERSION}/bin/sqlline -u jdbc:drill:zk:vagrant-99-00:2181
  #$(get_local_apps_path)/${DRILL_VERSION}/bin/drill-conf
  time_cmd_master "$drill_cmd" "$time_exec"

  # Stop metrics monitors and save bench (if needed)
  if [ "$time_exec" ] ; then
    set_bench_end "$bench"
    stop_monit
    save_disk_usage "AFTER"
    save_drill "$bench"
  fi
}

# Returns the the path to the drill binary with the proper exports
get_drill_cmd() {
  local drill_exports
  local drill_cmd
  export JAVA_HOME="$(get_java_home)"

  drill_exports="$(get_drill_exports)"
  drill_cmd="$drill_exports\n$(get_local_apps_path)/${DRILL_VERSION}/bin/sqlline -u jdbc:drill:zk:vagrant-99-00:2181 "
  echo -e "$drill_cmd"
}


# $1 bench name
save_drill() {
  logger "WARNING: missing to implement a proper save_drill()"
  stop_drill
  save_zookeeper
  save_hadoop "$bench_name"
  }