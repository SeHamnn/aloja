#!/usr/bin/env bash#!/usr/bin/env bash
#SETUP ZOOKEEPER SPECIFIC FUNCTIONS NOT OPTIMAL, TEST ONLY
source_file "$ALOJA_REPO_PATH/shell/common/common_hadoop.sh"
set_hadoop_requires


#source_file "$ALOJA_REPO_PATH/shell/common/common_zookeeper.sh"
#set_zookeeper_requires

# Sets the required files to download/copy
set_zookeeper_requires() {
  [ ! "$ZOOKEEPER_VERSION" ] && die "No DRILL_VERSION specified"

  BENCH_REQUIRED_FILES["$ZOOKEEPER_VERSION"]="http://mirror.serversupportforum.de/apache/zookeeper/$ZOOKEEPER_VERSION/$ZOOKEEPER_VERSION.tar.gz"

  #also set the config here
  BENCH_CONFIG_FOLDERS="$BENCH_CONFIG_FOLDERS zookeeper_conf"

}

# Helper to print a line with requiered exports
get_drill_exports() {
  local to_export

  to_export="$(get_hadoop_exports)
export ZOOKEEPER_VERSION='$ZOOKEEPER_VERSION';
export ZOOKEEPER_HOME='$(get_local_apps_path)/${ZOOKEEPER_VERSION}';
export ZOOKEEPER_CONF_DIR=$(get_local_apps_path)/${ZOOKEEPER_VERSION}/conf;
"

  echo -e "$to_export\n"
}


# start zookeeper
start_zookeeper(){
  local zookeeper_exports
  export JAVA_HOME="$(get_java_home)"

  zookeeper_exports="$(get_zookeeper_exports)"
  java -cp "$ZOOKEEPER_HOME/zookeeper.jar:lib/log4j-1.2.15.jar:conf" \ org.apache.zookeeper.server.quorum.QuorumPeerMain test.cfg
  java -cp "$ZOOKEEPER_HOME/zookeeper.jar:src/java/lib/log4j-1.2.15.jar:conf" \ org.apache.zookeeper.ZooKeeperMain 127.0.0.1:2181
}


# $1 bench name
save_zookeeper() {
  logger "WARNING: missing to implement a proper save_zookeeper()"
  save_hadoop "$bench_name"
  }