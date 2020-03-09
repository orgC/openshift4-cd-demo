# OCP4.3 离线安装 CICD 工具样本
本脚本用于离线部署Jenkins CI/CD demo，代码参考 https://github.com/siamaksade/openshift-cd-demo
本脚本仅用于演示用途，实际情况部署会有所调整。
OCP4.3 已将 jenkins pipeline 置于弃用状态，新项目可选基于 tekton 的 pipeline 实现。

## 前提

* 假定有本地quay/registry镜像仓库 registry.example.com:5000 ，如实际位置非本地址，需修改对应的yaml文件，纠正image下载位置。

* 假定已复制以下镜像到本地镜像仓库
```
skopeo copy docker://registry.redhat.io/openshift3/jenkins-agent-maven-35-rhel7:latest docker://registry.example.com:5000/openshift3/jenkins-agent-maven-35-rhel7:latest"
skopeo copy docker://docker.io/openshiftdemos/gogs:0.11.34 docker://registry.example.com:5000/openshiftdemos/gogs:0.11.34
skopeo copy docker://docker.io/sonatype/nexus3:3.13.0 docker://registry.example.com:5000/sonatype/nexus3:3.13.0
skopeo copy docker://docker.io/siamaksade/sonarqube:latest docker://registry.example.com:5000/siamaksade/sonarqube:latest
skopeo copy docker://registry.redhat.io/jboss-eap-7/eap72-openshift:latest docker://registry.example.com:5000/jboss-eap-7/eap72-openshift:latest
```

* 对应的 ocp4.3 已经修改镜像下载规则.
```
apiVersion: config.openshift.io/v1
kind: Image
metadata:
  name: cluster
spec:
  allowedRegistriesForImport:
    - domainName: registry.redhat.io
    - domainName: quay.io
    - domainName: docker.io
    - domainName: registry.connect.redhat.com
    - domainName: registry.access.redhat.com
    - domainName: 'registry.example.com:5000'
      insecure: true
  registrySources:
    allowedRegistries:
      - 'image-registry.openshift-image-registry.svc:5000'
      - registry.redhat.io
      - docker.io
      - quay.io
      - registry.access.redhat.com
      - registry.connect.redhat.com
      - 'registry.example.com:5000'
    insecureRegistries:
      - 'registry.example.com:5000'
```

## 安装

执行以下脚本
```
./provision.sh deploy --user <ocp_login_user> --quay-domain  registry.example.com:5000  --quay-username  <quay_username> --quay-password <quay_password>
```
