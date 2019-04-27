# devops-k8s

This is a daemon shell script for continuous integration, continuous delivery and continuous deployment with k8s. it will scan its located directory in k8s master nodes of clusters within interval one second for uploaded jar files, create dockerfiles with name *Dockerfile-\<appName>\-\<tag>*, build images with tag *\<appName>:\<tag>*  and security-copy those images across all joined nodes of k8s clusters, and then deploy pods and services within k8s clusters.

# Environment

- Kubernetes v1.14.1
- CentOS 7 
  - Kernel 3.10.0-862.el7.x86_64 GNU/Linux
- Docker
  - Docker version 18.09.5, build e8ff056

# Feature

- [x] Re-devops  Joined Nodes Broken-Before-Cured-After
- [x] Joined Nodes Auto-Detect
- [x] Devops Full-Cover Kubernetes Clusters
- [x] More

# Usage

1. Create and download this script *shell/devops.sh* to the directory *$HOME/devops/* in k8s master node of cluster ;
2.  Launch daemon script *devops.sh* by executing following commands  

```shell
cd $HOME/devops;chmod +x devops.sh;./devops.sh
```

3. Prepare k8s deployment and service yaml templates with given file name *\<appName>\-\<tag>-deployment.yaml* and service  *\<appNmae>\-\<tag>-svc.yaml* respectively in directory $HOME/devops/yaml, this is an optional, if you do not provide those yaml,  the default templates are supplied as below

    default *\<appName>\-\<tag>-deployment.yaml* 

   ```shell
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
   ```

   default  *\<appNmae>\-\<tag>-svc.yaml*

   ```shell
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
   ```

4. Upload your application jar file that wanted to deploy to k8s clusters to directory *$HOME/devops* , after done, your application will be auto integrated, delivered, and deployed to k8s clusters, enjoy it!
