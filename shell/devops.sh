#!/bin/sh
mkdir -p backup
mkdir -p yaml
mkdir -p logs
touch node-registry.txt
touch jar-registry.txt
host=`hostname`
while true; do
  test -e *.jar
  if [ $? == 0 ]; then
     for jar in `ls *.jar`; do
##   generate Dockerfile
       context=`ls $jar|awk -F'-' '{ print $1 } '`
       tag=`ls $jar|awk -F'-' '{ print $2 }'`
## check need to registry node or not
       ##jarRegi=`sed -n "$context:$tag" jar-registry.txt`
       count=`grep -c $context:$tag jar-registry.txt`
       ##if [[ -z $jarRegi ]]; then
       if [ $count == '0' ]; then
          echo "$context:$tag" >> jar-registry.txt
          for node in `kubectl get nodes|awk -F ' ' 'NR>1 { print $1 }'`; do
            if [ $host != $node ]; then
              echo $node:$context:$tag >> node-registry.txt
            fi
          done
       fi
     done
     for regi in `cat node-registry.txt`; do
       node=`echo $regi|awk -F':' '{ print $1}'`
       ssh -o NumberOfPasswordPrompts=0 root@$node "pwd" > /dev/null
       if [ $? == 0 ]; then
         context=`echo $regi|awk -F':' '{ print $2 }'`
         tag=`echo $regi|awk -F':' '{ print $3 }'`
         test -e $context-$tag*.jar
         if [ $? != 0 ]; then
            sed -i "/$context:$tag/d" node-registry.txt
            sed -i "/$context:$tag/d" jar-registry.txt
         else
           cat > Dockerfile << EOF
FROM openjdk
RUN mkdir -p /$context
ADD ["./$jar","/$context/"]
CMD java -jar /$context/$jar
EOF
##        ##build image
           docker image inspect $context:$tag > /dev/null 2>&1
           if [ $? == 0 ]; then
              docker rmi $context:$tag
           fi
           docker build -t $context:$tag ./
           docker save $context:$tag > /tmp/$context.tar.gz 
##       ##build images for all joined nodes
       # for node in `kubectl get nodes|awk -F ' ' 'NR>1 { print $1}'`; do
           if [ $host != $node ]; then
             scp -i ~/.ssh/id_rsa /tmp/$context.tar.gz root@$node:/tmp
             if [ $? == 0 ]; then
             ssh -i ~/.ssh/id_rsa root@$node > ./logs/ssh.log << EOF
docker rmi -f $context:$tag
docker load < /tmp/$context.tar.gz
exit
EOF
                if [ $? == 0 ]; then
                   sed -i "/$node/d" node-registry.txt
                fi
              fi
##           if [ $? == 0 ]; then
##            docker image inspect $context:$tag > /dev/null 2>&1
##            if [ $? == 0 ]; then
##               docker rmi $context:$tag > /dev/null 2>&1
##               if [ $? != 0 ]; then
##                  docker rmi -f $context:$tag
##               fi               
##            fi
##              docker rmi -f $context:$tag
##              docker load < /tmp/$context.tar.gz
##              exit
##           else
##             echo "cannot login $node"
##           fi
           fi   
       # done
         docker rmi $context:$tag
         deploy=`echo $context"_deployment".yaml`
         cat > ./yaml/$deploy << EOF
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: $context
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: $context
    spec:
      containers:
      - name: $context
        image: $context:$tag
        imagePullPolicy: IfNotPresent
        env:
        - name: CONIGURATION-SERVER
          value: wo-management-config
        - name: MYSQL-SERVER
          value: mysql
        - name: MYSQL-PORT
          value: "3306"
        - name: EUREKA-SERVER
          value: eureka
        - name: EUREKA-PORT
          value: "8000"
        ports:
        - containerPort: 8001
          hostPort: 8001
EOF
         svc=`echo $context"_svc".yaml`
         cat > ./yaml/$svc << EOF
apiVersion: v1
kind: Service
metadata:
 name: $context
 namespace: default
spec:
  selector:
   app: $context
  type: NodePort
  ports:
  - port: 8001
    targetPort: 8001
    nodePort: 30801
EOF
         kubectl apply -f ./yaml/$deploy
         kubectl apply -f ./yaml/$svc
     ## success=`sed -n "/$context:$tag/p" node-registry.txt`
     ## if [[ -z $success ]]; then
         success=`grep -c $context:$tag node-registry.txt`
         if [ $success == '0' ]; then
           sed -i "/$context:$tag/d" jar-registry.txt
           mv $jar ./backup
         fi
       fi
      fi 
    done
  else
    rm -f *-registry.txt
    echo "no jar file found!"
    sleep 1
  fi
done
