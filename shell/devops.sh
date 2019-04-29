#!/bin/sh
mkdir -p backup
mkdir -p yaml
mkdir -p logs
host=$(hostname)
while true; do
  ls *.jar > /dev/null 2>&1
  if [ $? == 0 ]; then
     touch node-registry.txt
     touch jar-registry.txt
     for jar in `ls *.jar`; do
       uploadDone=`flock -x -n $jar -c "echo ok"`
       if [ "$uploadDone" != "ok" ];then
          continue
       fi
##   generate Dockerfile
       appName=`ls $jar|awk -F'-' '{ print $1 } '`
       tag=`ls $jar|awk -F'-' '{ print $2 }'`
## check need to registry node or not
       count=`grep -c $appName:$tag jar-registry.txt`
       if [ $count == '0' ]; then
          echo "$appName:$tag" >> jar-registry.txt
          for node in `kubectl get nodes|awk -F ' ' 'NR>1 { print $1 }'`; do
            if [ $host != $node ]; then
              echo $node:$appName:$tag >> node-registry.txt
            fi
          done
       fi
     done
     for regi in `cat node-registry.txt`; do
       node=`echo $regi|awk -F':' '{ print $1}'`
       ssh -o NumberOfPasswordPrompts=0 root@$node "pwd" > /dev/null
       if [ $? == 0 ]; then
         appName=`echo $regi|awk -F':' '{ print $2 }'`
         tag=`echo $regi|awk -F':' '{ print $3 }'`
         test -e $appName-$tag*.jar
         if [ $? != 0 ]; then
            sed -i "/$appName:$tag/d" node-registry.txt
            sed -i "/$appName:$tag/d" jar-registry.txt
         else
           jar=`ls $appName-$tag*.jar`
           test -e Dockerfile-$appName-$tag
           if [ $? != 0 ]; then
             cat > Dockerfile-$appName-$tag << EOF
FROM openjdk
RUN mkdir -p /$appName
ADD ["./$jar","/$appName/"]
CMD java -jar /$appName/$jar
EOF
##        ##build image
             docker image inspect $appName:$tag > /dev/null 2>&1
             if [ $? == 0 ]; then
                docker rmi  -f $appName:$tag
             fi
             docker build -t $appName:$tag -f Dockerfile-$appName-$tag ./
             docker save $appName:$tag > /tmp/$appName-$tag.tar.gz
           fi 
##       ##build images for all joined nodes
           if [ $host != $node ]; then
             scp -i ~/.ssh/id_rsa /tmp/$appName-$tag.tar.gz root@$node:/tmp
             if [ $? == 0 ]; then
             ssh -i ~/.ssh/id_rsa root@$node > ./logs/ssh.log << EOF
docker rmi -f $appName:$tag
docker load < /tmp/$appName-$tag.tar.gz
rm -f /tmp/$appName-$tag.tar.gz
exit
EOF
                if [ $? == 0 ]; then
                   sed -i "/$node/d" node-registry.txt
                fi
              fi
           fi   
         deploy=`echo $appName-$tag"-deployment".yaml`
         test -e ./yaml/$deploy
         if [ $? != 0 ]; then
           cat > ./yaml/$deploy << EOF
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: $appName
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: $appName
    spec:
      containers:
      - name: $appName
        image: $appName:$tag
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 39001
          hostPort: 39001
EOF
         fi
         svc=`echo $appName-$tag"-svc".yaml`
         test -e ./yaml/$svc
         if [ $? != 0 ]; then
           cat > ./yaml/$svc << EOF
apiVersion: v1
kind: Service
metadata:
 name: $appName
 namespace: default
spec:
  selector:
   app: $appName
  ports:
  - port: 38001
    targetPort: 38001
EOF
         fi
         kubectl apply -f ./yaml/$deploy
         kubectl apply -f ./yaml/$svc
         success=`grep -c $appName:$tag node-registry.txt`
         if [ $success == '0' ]; then
           docker rmi -f $appName:$tag
           sed -i "/$appName:$tag/d" jar-registry.txt
           mv $jar ./backup
           rm -f Dockerfile-$appName-$tag
           rm -f /tmp/$appName-$tag.tar.gz
         fi
       fi
      fi 
    done
  else
    rm -f Dockerfile*
    echo "no jar file found!"
    sleep 1
  fi
done
