#!/bin/bash

echo "###############################################################################"
echo "#  MAKE SURE YOU ARE LOGGED IN:                                               #"
echo "#  $ oc login http://console.your.openshift.com                               #"
echo "###############################################################################"

BASE_FOLDER=$(cd "$(dirname "$0")/..";pwd)

function usage() {
    echo
    echo "Usage:"
    echo " $0 [command] [options]"
    echo " $0 --help"
    echo
    echo "Example:"
    echo " $0 deploy --project-suffix mydemo"
    echo
    echo "COMMANDS:"
    echo "   deploy                   Set up the demo projects and deploy demo apps"
    echo "   delete                   Clean up and remove demo projects and objects"
    echo "   idle                     Make all demo services idle"
    echo "   unidle                   Make all demo services unidle"
    echo
    echo "OPTIONS:"
    echo "   --enable-quay              Optional    使用内部仓库 Enable integration of build and deployments with quay."
    echo "   --quay-domain              Optional    使用内部仓库地址 registry.ocp43.io:5000 ."
    echo "   --quay-username            Optional    quay username to push the images to a quay.io account. Required if --enable-quay is set"
    echo "   --quay-password            Optional    quay password to push the images to a quay.io account. Required if --enable-quay is set"
    echo "   --user [username]          Optional    The admin user for the demo projects. Required if logged in as system:admin"
    echo "   --project-suffix [suffix]  Optional    Suffix to be added to demo project names e.g. ci-SUFFIX. If empty, user will be used as suffix"
    echo "   --ephemeral                Optional    Deploy demo without persistent storage. Default false"
    echo "   --oc-options               Optional    oc client options to pass to all oc commands e.g. --server https://my.openshift.com"
    echo ""
    echo "假定以下几个镜像已经存放于 registry.ocp43.io:5000 仓库,如果位置变化需修改各自 ImageStream 下载位置.本脚本默认OCP4能上registry.redhat.io下载镜像,如果不可行，按离线处理镜像下载"
    echo "skopeo copy docker://registry.redhat.io/openshift3/jenkins-agent-maven-35-rhel7:latest docker://registry.ocp43.io:5000/openshift3/jenkins-agent-maven-35-rhel7:latest"
    echo "skopeo copy docker://docker.io/openshiftdemos/gogs:0.11.34 docker://registry.ocp43.io:5000/openshiftdemos/gogs:0.11.34"
    echo "skopeo copy docker://docker.io/sonatype/nexus3:3.13.0 docker://registry.ocp43.io:5000/sonatype/nexus3:3.13.0"
    echo "skopeo copy docker://docker.io/siamaksade/sonarqube:latest docker://registry.ocp43.io:5000/siamaksade/sonarqube:latest"
    echo "skopeo copy docker://registry.redhat.io/jboss-eap-7/eap72-openshift:latest docker://registry.ocp43.io:5000/jboss-eap-7/eap72-openshift:latest"
    echo ""

# 对应的 ocp4 需要修改镜像下载规则.
# apiVersion: config.openshift.io/v1
# kind: Image
# metadata:
#   name: cluster
# spec:
#   allowedRegistriesForImport:
#     - domainName: registry.redhat.io
#     - domainName: quay.io
#     - domainName: docker.io
#     - domainName: registry.connect.redhat.com
#     - domainName: 'registry.ocp43.io:5000'
#       insecure: true
#   registrySources:
#     allowedRegistries:
#       - 'image-registry.openshift-image-registry.svc:5000'
#       - registry.redhat.io
#       - docker.io
#       - quay.io
#       - registry.connect.redhat.com
#       - 'registry.ocp43.io:5000'
#     insecureRegistries:
#       - 'registry.ocp43.io:5000'

}

ARG_USERNAME=
ARG_PROJECT_SUFFIX=
ARG_COMMAND=
ARG_EPHEMERAL=false
ARG_OC_OPS=
ARG_ENABLE_QUAY=false
ARG_QUAY_DOMAIN=
ARG_QUAY_USER=
ARG_QUAY_PASS=

while :; do
    case $1 in
        deploy)
            ARG_COMMAND=deploy
            ;;
        delete)
            ARG_COMMAND=delete
            ;;
        idle)
            ARG_COMMAND=idle
            ;;
        unidle)
            ARG_COMMAND=unidle
            ;;
        --user)
            if [ -n "$2" ]; then
                ARG_USERNAME=$2
                shift
            else
                printf 'ERROR: "--user" requires a non-empty value.\n' >&2
                usage
                exit 255
            fi
            ;;
        --project-suffix)
            if [ -n "$2" ]; then
                ARG_PROJECT_SUFFIX=$2
                shift
            else
                printf 'ERROR: "--project-suffix" requires a non-empty value.\n' >&2
                usage
                exit 255
            fi
            ;;
        --oc-options)
            if [ -n "$2" ]; then
                ARG_OC_OPS=$2
                shift
            else
                printf 'ERROR: "--oc-options" requires a non-empty value.\n' >&2
                usage
                exit 255
            fi
            ;;
        --enable-quay)
            ARG_ENABLE_QUAY=false
            ;;
        --quay-domain)
            if [ -n "$2" ]; then
                ARG_QUAY_DOMAIN=$2
                shift
            else
                printf 'ERROR: "--quay-domain" requires a non-empty value.\n' >&2
                usage
                exit 255
            fi
            ;;
        --quay-username)
            if [ -n "$2" ]; then
                ARG_QUAY_USER=$2
                shift
            else
                printf 'ERROR: "--quay-username" requires a non-empty value.\n' >&2
                usage
                exit 255
            fi
            ;;
        --quay-password)
            if [ -n "$2" ]; then
                ARG_QUAY_PASS=$2
                shift
            else
                printf 'ERROR: "--quay-password" requires a non-empty value.\n' >&2
                usage
                exit 255
            fi
            ;;
        --ephemeral)
            ARG_EPHEMERAL=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -?*)
            printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
            shift
            ;;
        *) # Default case: If no more options then break out of the loop.
            break
    esac

    shift
done


################################################################################
# CONFIGURATION                                                                #
################################################################################

LOGGEDIN_USER=$(oc $ARG_OC_OPS whoami)
OPENSHIFT_USER=${ARG_USERNAME:-$LOGGEDIN_USER}
PRJ_SUFFIX=${ARG_PROJECT_SUFFIX:-`echo $OPENSHIFT_USER | sed -e 's/[-@].*//g'`}

function deploy() {
  oc $ARG_OC_OPS new-project dev-$PRJ_SUFFIX   --display-name="Tasks - Dev"
  oc $ARG_OC_OPS new-project stage-$PRJ_SUFFIX --display-name="Tasks - Stage"
  oc $ARG_OC_OPS new-project cicd-$PRJ_SUFFIX  --display-name="CI/CD"

  sleep 2

  oc $ARG_OC_OPS policy add-role-to-group edit system:serviceaccounts:cicd-$PRJ_SUFFIX -n dev-$PRJ_SUFFIX
  oc $ARG_OC_OPS policy add-role-to-group edit system:serviceaccounts:cicd-$PRJ_SUFFIX -n stage-$PRJ_SUFFIX

  if [ $LOGGEDIN_USER == 'system:admin' ] ; then
    oc $ARG_OC_OPS adm policy add-role-to-user admin $ARG_USERNAME -n dev-$PRJ_SUFFIX >/dev/null 2>&1
    oc $ARG_OC_OPS adm policy add-role-to-user admin $ARG_USERNAME -n stage-$PRJ_SUFFIX >/dev/null 2>&1
    oc $ARG_OC_OPS adm policy add-role-to-user admin $ARG_USERNAME -n cicd-$PRJ_SUFFIX >/dev/null 2>&1

    oc $ARG_OC_OPS annotate --overwrite namespace dev-$PRJ_SUFFIX   demo=openshift-cd-$PRJ_SUFFIX >/dev/null 2>&1
    oc $ARG_OC_OPS annotate --overwrite namespace stage-$PRJ_SUFFIX demo=openshift-cd-$PRJ_SUFFIX >/dev/null 2>&1
    oc $ARG_OC_OPS annotate --overwrite namespace cicd-$PRJ_SUFFIX  demo=openshift-cd-$PRJ_SUFFIX >/dev/null 2>&1

    oc $ARG_OC_OPS adm pod-network join-projects --to=cicd-$PRJ_SUFFIX dev-$PRJ_SUFFIX stage-$PRJ_SUFFIX >/dev/null 2>&1

  fi

  sleep 2

  oc new-app jenkins-persistent -p VOLUME_CAPACITY=4Gi  -n cicd-$PRJ_SUFFIX

  sleep 2

  WEBHOOK_SECRET=MimaBuNengGaoSuNi
   
  oc $ARG_OC_OPS new-app -f $BASE_FOLDER/cicd-template.yaml -p DEV_PROJECT=dev-$PRJ_SUFFIX -p STAGE_PROJECT=stage-$PRJ_SUFFIX -p EPHEMERAL=$ARG_EPHEMERAL -p ENABLE_QUAY=$ARG_ENABLE_QUAY -p QUAY_DOMAIN=$ARG_QUAY_DOMAIN -p QUAY_USERNAME=$ARG_QUAY_USER -p QUAY_PASSWORD=$ARG_QUAY_PASS -p WEBHOOK_SECRET=$WEBHOOK_SECRET -n cicd-$PRJ_SUFFIX


  sleep 4
  oc project cicd-$PRJ_SUFFIX
  # adjust jenkins
  oc set resources dc/jenkins --limits=cpu=2,memory=2Gi --requests=cpu=100m,memory=512Mi -n cicd-$PRJ_SUFFIX
  oc set env dc/jenkins JENKINS_JAVA_OVERRIDES="-Dhudson.model.LoadStatistics.clock=2000 -Dhudson.slaves.NodeProvisioner.recurrencePeriod=2000 -Dhudson.slaves.NodeProvisioner.initialDelay=0 -Dhudson.slaves.NodeProvisioner.MARGIN=50 -Dhudson.slaves.NodeProvisioner.MARGIN0=0.85" -n cicd-$PRJ_SUFFIX
  oc label dc jenkins app=jenkins --overwrite -n cicd-$PRJ_SUFFIX

  oc create secret docker-registry quay-cicd-secret --docker-server=$ARG_QUAY_DOMAIN --docker-username="$ARG_QUAY_USER" --docker-password="$ARG_QUAY_PASS" --docker-email=cicd@redhat.com -n cicd-$PRJ_SUFFIX
  if [ "$ARG_ENABLE_QUAY" == "true" ] ; then
    # cicd
    oc create secret generic quay-cicd-secret --from-literal="username=$ARG_QUAY_USER" --from-literal="password=$ARG_QUAY_PASS" -n cicd-$PRJ_SUFFIX
    oc label secret quay-cicd-secret credential.sync.jenkins.openshift.io=true -n cicd-$PRJ_SUFFIX

    # dev
    oc create secret docker-registry quay-cicd-secret --docker-server=$ARG_QUAY_DOMAIN --docker-username="$ARG_QUAY_USER" --docker-password="$ARG_QUAY_PASS" --docker-email=cicd@redhat.com -n dev-$PRJ_SUFFIX
    oc new-build --name=tasks --image-stream=openshift/eap-cd-openshift:14 --binary=true --push-secret=quay-cicd-secret --to-docker --to='$ARG_QUAY_DOMAIN/$ARG_QUAY_USER/tasks-app:latest' -n dev-$PRJ_SUFFIX
    oc new-app --name=tasks --docker-image=$ARG_QUAY_DOMAIN/$ARG_QUAY_USER/tasks-app:latest --allow-missing-images -n dev-$PRJ_SUFFIX
    oc set triggers dc tasks --remove-all -n dev-$PRJ_SUFFIX
    oc patch dc tasks -p '{"spec": {"template": {"spec": {"containers": [{"name": "tasks", "imagePullPolicy": "Always"}]}}}}' -n dev-$PRJ_SUFFIX
    oc delete is tasks -n dev-$PRJ_SUFFIX
    oc secrets link default quay-cicd-secret --for=pull -n dev-$PRJ_SUFFIX

    # stage
    oc create secret docker-registry quay-cicd-secret --docker-server=$ARG_QUAY_DOMAIN --docker-username="$ARG_QUAY_USER" --docker-password="$ARG_QUAY_PASS" --docker-email=cicd@redhat.com -n stage-$PRJ_SUFFIX
    oc new-app --name=tasks --docker-image=$ARG_QUAY_DOMAIN/$ARG_QUAY_USER/tasks-app:stage --allow-missing-images -n stage-$PRJ_SUFFIX
    oc set triggers dc tasks --remove-all -n stage-$PRJ_SUFFIX
    oc patch dc tasks -p '{"spec": {"template": {"spec": {"containers": [{"name": "tasks", "imagePullPolicy": "Always"}]}}}}' -n stage-$PRJ_SUFFIX
    oc delete is tasks -n stage-$PRJ_SUFFIX
    oc secrets link default quay-cicd-secret --for=pull -n stage-$PRJ_SUFFIX
  else
    # dev
    oc new-build --name=tasks --image-stream=openshift/eap-cd-openshift:14 --binary=true -n dev-$PRJ_SUFFIX
    oc new-app tasks:latest --allow-missing-images -n dev-$PRJ_SUFFIX
    oc set triggers dc -l app=tasks --containers=tasks --from-image=tasks:latest --manual -n dev-$PRJ_SUFFIX

    # stage
    oc new-app tasks:stage --allow-missing-images -n stage-$PRJ_SUFFIX
    oc set triggers dc -l app=tasks --containers=tasks --from-image=tasks:stage --manual -n stage-$PRJ_SUFFIX
  fi

  # dev project
  oc expose dc/tasks --port=8080 -n dev-$PRJ_SUFFIX
  oc expose svc/tasks -n dev-$PRJ_SUFFIX
  oc set probe dc/tasks --readiness --get-url=http://:8080/ws/demo/healthcheck --initial-delay-seconds=30 --failure-threshold=10 --period-seconds=10 -n dev-$PRJ_SUFFIX
  oc set probe dc/tasks --liveness  --get-url=http://:8080/ws/demo/healthcheck --initial-delay-seconds=180 --failure-threshold=10 --period-seconds=10 -n dev-$PRJ_SUFFIX
  oc rollout cancel dc/tasks -n stage-$PRJ_SUFFIX

  # stage project
  oc expose dc/tasks --port=8080 -n stage-$PRJ_SUFFIX
  oc expose svc/tasks -n stage-$PRJ_SUFFIX
  oc set probe dc/tasks --readiness --get-url=http://:8080/ws/demo/healthcheck --initial-delay-seconds=30 --failure-threshold=10 --period-seconds=10 -n stage-$PRJ_SUFFIX
  oc set probe dc/tasks --liveness  --get-url=http://:8080/ws/demo/healthcheck --initial-delay-seconds=180 --failure-threshold=10 --period-seconds=10 -n stage-$PRJ_SUFFIX
  oc rollout cancel dc/tasks -n dev-$PRJ_SUFFIX

  # deploy gogs
  HOSTNAME=$(oc get route jenkins -o template --template='{{.spec.host}}' | sed "s/jenkins-cicd-$PRJ_SUFFIX.//g")
  GOGS_HOSTNAME="gogs-cicd-$PRJ_SUFFIX.$HOSTNAME"

  if [ "$ARG_EPHEMERAL" == "true" ] ; then
    oc new-app -f $BASE_FOLDER/gogs-template.yaml \
        --param=GOGS_VERSION=0.11.34 \
        --param=DATABASE_VERSION=9.6 \
        --param=HOSTNAME=$GOGS_HOSTNAME \
        --param=SKIP_TLS_VERIFY=true
  else
    oc new-app -f $BASE_FOLDER/gogs-persistent-template.yaml \
        --param=GOGS_VERSION=0.11.34 \
        --param=DATABASE_VERSION=9.6 \
        --param=HOSTNAME=$GOGS_HOSTNAME \
        --param=SKIP_TLS_VERIFY=true
  fi

  sleep 5

  if [ "$ARG_EPHEMERAL" == "true" ] ; then
    oc new-app -f $BASE_FOLDER/sonarqube-template.yaml --param=SONARQUBE_MEMORY_LIMIT=2Gi
  else
    oc new-app -f $BASE_FOLDER/sonarqube-persistent-template.yaml --param=SONARQUBE_MEMORY_LIMIT=4Gi
  fi

  oc set resources dc/sonardb --limits=cpu=200m,memory=512Mi --requests=cpu=50m,memory=128Mi
  oc set resources dc/sonarqube --limits=cpu=2,memory=4Gi --requests=cpu=50m,memory=128Mi

  if [ "$ARG_EPHEMERAL" == "true" ] ; then
    oc new-app -f $BASE_FOLDER/nexus3-template.yaml  --param=NEXUS_VERSION=3.13.0 --param=MAX_MEMORY=3Gi
  else
    local template=
    oc new-app -f $BASE_FOLDER/nexus3-persistent-template.yaml --param=NEXUS_VERSION=3.13.0 --param=MAX_MEMORY=4Gi --param=VOLUME_CAPACITY=20Gi
  fi

  oc set resources dc/nexus --requests=cpu=200m --limits=cpu=2

  GOGS_ROUTE=$(oc get route gogs -o template --template='{{.spec.host}}' -n cicd-$PRJ_SUFFIX )
  GOGS_USER=gogs
  GOGS_PWD=gogs

  oc rollout status dc gogs
  sleep 30

  _RETURN=$(curl -o /tmp/curl.log -sL --post302 -w "%{http_code}" http://$GOGS_ROUTE/user/sign_up \
    --form user_name=$GOGS_USER \
    --form password=$GOGS_PWD \
    --form retype=$GOGS_PWD \
    --form email=admin@gogs.com)


  if [ $_RETURN != "200" ] && [ $_RETURN != "302" ] ; then
    echo "ERROR: Failed to create Gogs admin"
    cat /tmp/curl.log
    //exit 255
  fi


  cat <<EOF > /tmp/data.json
{
  "name": "openshift-tasks",
  "description": "This is openshift-tasks"
}
EOF

  _RETURN=$(curl -o /tmp/curl.log -sL -w "%{http_code}" -H "Content-Type: application/json" \
  -u $GOGS_USER:$GOGS_PWD -X POST http://$GOGS_ROUTE/api/v1/user/repos -d @/tmp/data.json)

  if [ $_RETURN != "201" ] ;then
    echo "ERROR: Failed to new openshift-tasks repo"
    cat /tmp/curl.log
    exit 255
  fi
  
  cd $BASE_FOLDER/openshift-tasks
  git init
  git add *
  git commit -m "first commit"
  git remote add origin http://$GOGS_USER:$GOGS_PWD@$GOGS_ROUTE/$GOGS_USER/openshift-tasks.git
  git push -u origin master 
  sleep 5
  cd $BASE_FOLDER

  cat <<EOF > /tmp/data.json
{
  "type": "gogs",
  "config": {
    "url": "https://openshift.default.svc.cluster.local/apis/build.openshift.io/v1/namespaces/cicd-$PRJ_SUFFIX/buildconfigs/tasks-pipeline/webhooks/$WEBHOOK_SECRET/generic",
    "content_type": "json"
  },
  "events": [
    "push"
  ],
  "active": true
}
EOF

  _RETURN=$(curl -o /tmp/curl.log -sL -w "%{http_code}" -H "Content-Type: application/json" \
  -u $GOGS_USER:$GOGS_PWD -X POST http://$GOGS_ROUTE/api/v1/repos/$GOGS_USER/openshift-tasks/hooks -d @/tmp/data.json)

  if [ $_RETURN != "201" ] ; then
    echo "ERROR: Failed to set webhook"
    cat /tmp/curl.log
    exit 255
  fi

  oc label dc sonarqube "app.kubernetes.io/part-of"="sonarqube" --overwrite
  oc label dc sonardb "app.kubernetes.io/part-of"="sonarqube" --overwrite
  oc label dc jenkins "app.kubernetes.io/part-of"="jenkins" --overwrite
  oc label dc nexus "app.kubernetes.io/part-of"="nexus" --overwrite
  oc label dc gogs "app.kubernetes.io/part-of"="gogs" --overwrite
  oc label dc gogs-postgresql "app.kubernetes.io/part-of"="gogs" --overwrite
}

function make_idle() {
  echo_header "Idling Services"
  oc $ARG_OC_OPS idle -n dev-$PRJ_SUFFIX --all
  oc $ARG_OC_OPS idle -n stage-$PRJ_SUFFIX --all
  oc $ARG_OC_OPS idle -n cicd-$PRJ_SUFFIX --all
}

function make_unidle() {
  echo_header "Unidling Services"
  local _DIGIT_REGEX="^[[:digit:]]*$"

  for project in dev-$PRJ_SUFFIX stage-$PRJ_SUFFIX cicd-$PRJ_SUFFIX
  do
    for dc in $(oc $ARG_OC_OPS get dc -n $project -o=custom-columns=:.metadata.name); do
      local replicas=$(oc $ARG_OC_OPS get dc $dc --template='{{ index .metadata.annotations "idling.alpha.openshift.io/previous-scale"}}' -n $project 2>/dev/null)
      if [[ $replicas =~ $_DIGIT_REGEX ]]; then
        oc $ARG_OC_OPS scale --replicas=$replicas dc $dc -n $project
      fi
    done
  done
}

function set_default_project() {
  if [ $LOGGEDIN_USER == 'system:admin' ] ; then
    oc $ARG_OC_OPS project default >/dev/null
  fi
}

function remove_storage_claim() {
  local _DC=$1
  local _VOLUME_NAME=$2
  local _CLAIM_NAME=$3
  local _PROJECT=$4
  oc $ARG_OC_OPS volumes dc/$_DC --name=$_VOLUME_NAME --add -t emptyDir --overwrite -n $_PROJECT
  oc $ARG_OC_OPS delete pvc $_CLAIM_NAME -n $_PROJECT >/dev/null 2>&1
}

function echo_header() {
  echo
  echo "########################################################################"
  echo $1
  echo "########################################################################"
}

################################################################################
# MAIN: DEPLOY DEMO                                                            #
################################################################################

if [ "$LOGGEDIN_USER" == 'system:admin' ] && [ -z "$ARG_USERNAME" ] ; then
  # for verify and delete, --project-suffix is enough
  if [ "$ARG_COMMAND" == "delete" ] || [ "$ARG_COMMAND" == "verify" ] && [ -z "$ARG_PROJECT_SUFFIX" ]; then
    echo "--user or --project-suffix must be provided when running $ARG_COMMAND as 'system:admin'"
    exit 255
  # deploy command
  elif [ "$ARG_COMMAND" != "delete" ] && [ "$ARG_COMMAND" != "verify" ] ; then
    echo "--user must be provided when running $ARG_COMMAND as 'system:admin'"
    exit 255
  fi
fi
echo $PWD
pushd ~ >/dev/null
START=`date +%s`

echo_header "OpenShift CI/CD Demo ($(date))"

case "$ARG_COMMAND" in
    delete)
        echo "Delete demo..."
        oc $ARG_OC_OPS delete project dev-$PRJ_SUFFIX stage-$PRJ_SUFFIX cicd-$PRJ_SUFFIX
        echo
        echo "Delete completed successfully!"
        ;;

    idle)
        echo "Idling demo..."
        make_idle
        echo
        echo "Idling completed successfully!"
        ;;

    unidle)
        echo "Unidling demo..."
        make_unidle
        echo
        echo "Unidling completed successfully!"
        ;;

    deploy)
        echo "Deploying demo..."
        deploy
        echo
        echo "Provisioning completed successfully!"
        ;;

    *)
        echo "Invalid command specified: '$ARG_COMMAND'"
        usage
        ;;
esac

set_default_project
popd >/dev/null

END=`date +%s`
echo "(Completed in $(( ($END - $START)/60 )) min $(( ($END - $START)%60 )) sec)"
