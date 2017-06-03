dataDir=$1
rm $dataDir/myid
mkdir $dataDir 
host="$HOSTNAME"
c="${host: -1}"
logger "ZK ID: $c"
echo $((c+1)) > $dataDir/myid
cat $dataDir/myid