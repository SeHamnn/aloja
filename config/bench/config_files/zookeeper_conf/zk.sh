k=$1
string="tickTime=2000
initLimit=10
syncLimit=5
dataDir=/tmp/zookeeper
clientPort=2181"

for ((c=0; c<$k; c++))
do
	if ((c%2==0))
	then
		number=$((1+$c/2))
		string+="\nServer.$number=vagrant-99-0$c:2888:3888"
	fi
done
echo -e "$string" > zoo.cfg