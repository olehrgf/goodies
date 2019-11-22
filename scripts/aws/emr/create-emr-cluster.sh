#!/bin/bash

command -v aws >/dev/null 2>&1 || {
  echo >&2 "'aws cli' reqiered but it's not installed.  Aborting."
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo >&2 "'jq' required but it's not installed.  Aborting."
  exit 1
}

SSH_KEY_NAME=
PROFILE=
PATH_TO_BOOTSTRAP_ACTION=
PATH_TO_EXTRAS=
PATH_TO_CONFIG='./software-config/'
INSTANCE_GROUPE_CONFIG=
CLUSTER_SETTINGS_CONFIG=
EC2_ATTRIBUTES_CONFIG=
CLUSTER_NAME='spark-jobs'
EMR_VERSION='emr-5.27.0'
EMR_REGION='us-west-2'
BUNDLE_PROFILE='reduced'

AWS_ACCESS_KEY="$AWS_ACCESS_KEY_ID"
AWS_SECRET_KEY="$AWS_SECRET_ACCESS_KEY"
AWS_GLUE_CATALOG_ID="$AWS_GLUE_CATALOG_ID"
AWS_EC2_SUBNET_ID=''

while [[ $# -gt 0 ]]; do
  case "$1" in
  --ssh-key)
    SSH_KEY_NAME="$2"
    shift
    shift
    ;;
  --path-to-bootstrap-action)
    PATH_TO_BOOTSTRAP_ACTION="$2"
    shift
    shift
    ;;
  --path-to-extras)
    PATH_TO_EXTRAS="$2"
    shift
    shift
    ;;
  --path-to-config)
    PATH_TO_CONFIG="$2"
    shift
    shift
    ;;
  --path-to-instance-group-config)
    INSTANCE_GROUPE_CONFIG="$2"
    shift
    shift
    ;;
  --path-to-cluster-settings)
    CLUSTER_SETTINGS_CONFIG="$2"
    shift
    shift
    ;;
  --path-to-ec2-attributes)
    EC2_ATTRIBUTES_CONFIG="$2"
    shift
    shift
    ;;
  --profile)
    PROFILE="--profile=$2"
    shift
    shift
    ;;
  --name)
    CLUSTER_NAME="$2"
    shift
    shift
    ;;
  --region)
    EMR_REGION="$2"
    shift
    shift
    ;;
  --bundle-profile)
    BUNDLE_PROFILE="$2"
    shift
    shift
    ;;
  --aws-access-key)
    AWS_ACCESS_KEY="$2"
    shift
    shift
    ;;
  --aws-secret-key)
    AWS_SECRET_KEY="$2"
    shift
    shift
    ;;
  --aws-glue-catalog-id)
    AWS_GLUE_CATALOG_ID="$2"
    shift
    shift
    ;;
  --aws-ec2-subnet-id)
    AWS_EC2_SUBNET_ID="$2"
    shift
    shift
    ;;
  *)
    printf "***************************\n"
    printf "* Error: Invalid argument.*\n"
    printf "***************************\n"
    exit 1
    ;;
  esac
done

CURRENT_ACCOUNT_ID=$(aws sts get-caller-identity "$PROFILE" | jq -r '.Account')

INSTANCE_GROUPE_CONFIG_FILE_NAME="/emr-cluster-instance-group-config.json"
CLUSTER_SETTINGS_CONFIG_FILE_NAME="/aws-emr-spark-cluster-settings.json"
EC2_ATTRIBUTES_CONFIG_FILE_NAME="/ec2-attributes.json"

if [[ "$PATH_TO_CONFIG" == */ ]]; then
  PATH_TO_CONFIG=$(echo "$PATH_TO_CONFIG" | sed 's:/*$::')
fi

if [ -z "${INSTANCE_GROUPE_CONFIG}" ]; then
  INSTANCE_GROUPE_CONFIG="$PATH_TO_CONFIG$INSTANCE_GROUPE_CONFIG_FILE_NAME"
fi

if [ -z "${CLUSTER_SETTINGS_CONFIG}" ]; then
  CLUSTER_SETTINGS_CONFIG="$PATH_TO_CONFIG$CLUSTER_SETTINGS_CONFIG_FILE_NAME"
fi

if [ -z "${EC2_ATTRIBUTES_CONFIG}" ]; then
  EC2_ATTRIBUTES_CONFIG="$PATH_TO_CONFIG$EC2_ATTRIBUTES_CONFIG_FILE_NAME"
fi

if [[ "$INSTANCE_GROUPE_CONFIG" == s3://* ]]; then
  aws s3 cp --quiet "$PROFILE" "$INSTANCE_GROUPE_CONFIG" ./.tmp_sc$INSTANCE_GROUPE_CONFIG_FILE_NAME
else
  mv "$INSTANCE_GROUPE_CONFIG" ./.tmp_sc$INSTANCE_GROUPE_CONFIG_FILE_NAME
fi
INSTANCE_GROUPE_CONFIG="/${PWD}/.tmp_sc$INSTANCE_GROUPE_CONFIG_FILE_NAME"

if [[ "$CLUSTER_SETTINGS_CONFIG" == s3://* ]]; then
  aws s3 cp --quiet "$PROFILE" "$CLUSTER_SETTINGS_CONFIG" ./.tmp_sc$CLUSTER_SETTINGS_CONFIG_FILE_NAME
else
  mv "$CLUSTER_SETTINGS_CONFIG" ./.tmp_sc$CLUSTER_SETTINGS_CONFIG_FILE_NAME
fi
CLUSTER_SETTINGS_CONFIG="/${PWD}/.tmp_sc$CLUSTER_SETTINGS_CONFIG_FILE_NAME"

if [[ "$EC2_ATTRIBUTES_CONFIG" == s3://* ]]; then
  aws s3 cp --quiet "$PROFILE" "$EC2_ATTRIBUTES_CONFIG" ./.tmp_sc$EC2_ATTRIBUTES_CONFIG_FILE_NAME
else
  mv "$EC2_ATTRIBUTES_CONFIG" ./.tmp_sc$EC2_ATTRIBUTES_CONFIG_FILE_NAME
fi
EC2_ATTRIBUTES_CONFIG="/${PWD}/.tmp_sc$EC2_ATTRIBUTES_CONFIG_FILE_NAME"

if [ -z "${AWS_ACCESS_KEY}" ] && [ -z "${AWS_SECRET_KEY}" ] && [ -z "${AWS_GLUE_CATALOG_ID}" ]; then
  jq '(.[].Properties)|=(map_values((if . == "$awsAccessKeyId" then .=$awsAccessKeyId elif . == "$awsSecretAccessKey" then .=$awsSecretAccessKey elif . == "$catalogId" then .=$catalogId else . end)))' \
    --arg awsAccessKeyId "$AWS_ACCESS_KEY" \
    --arg awsSecretAccessKey "$AWS_SECRET_KEY" \
    --arg catalogId "$AWS_GLUE_CATALOG_ID" \
    "$CLUSTER_SETTINGS_CONFIG" >"$CLUSTER_SETTINGS_CONFIG.updated"
else
  cat "$CLUSTER_SETTINGS_CONFIG" >"$CLUSTER_SETTINGS_CONFIG.updated"
fi
CLUSTER_SETTINGS_CONFIG="$CLUSTER_SETTINGS_CONFIG.updated"

if [ -z "${AWS_EC2_SUBNET_ID}" ]; then
  jq '(.[])|=(map_values((if . == "$subnetId" then .=$subnetId else . end)))' \
    --arg subnetId "$AWS_EC2_SUBNET_ID" \
    "$EC2_ATTRIBUTES_CONFIG" >"$EC2_ATTRIBUTES_CONFIG.updated"
else
  cat "$EC2_ATTRIBUTES_CONFIG" >"$EC2_ATTRIBUTES_CONFIG.updated"
fi
EC2_ATTRIBUTES_CONFIG="$EC2_ATTRIBUTES_CONFIG.updated"

EC2_ATTRIBUTES="$(jq -c '.[0]' "$EC2_ATTRIBUTES_CONFIG")"
if [ -n "${SSH_KEY_NAME}" ]; then
  EC2_ATTRIBUTES="$(jq -c '.[0].KeyName=$sshKey|.[0]' --arg sshKey "$SSH_KEY_NAME" "$EC2_ATTRIBUTES_CONFIG")"
fi

CREATE_CLUSTER_ARGS=(
  --applications Name=Hadoop Name=Ganglia Name=Spark
  --tags "Name=$CLUSTER_NAME" "Stack=$CLUSTER_NAME"
  --ec2-attributes "$EC2_ATTRIBUTES"
  --release-label "$EMR_VERSION"
  --log-uri 's3n://aws-logs-'"$CURRENT_ACCOUNT_ID"'-'"$EMR_REGION"'/elasticmapreduce/'
  --instance-groups "file:/$INSTANCE_GROUPE_CONFIG"
  --configurations "file:/$CLUSTER_SETTINGS_CONFIG"
  --auto-scaling-role "EMR_AutoScaling_DefaultRole"
  --ebs-root-volume-size 32
  --service-role EMR_DefaultRole
  --name "$CLUSTER_NAME"
)

if [ -n "$EMR_REGION" ]; then
  CREATE_CLUSTER_ARGS+=(--region "$EMR_REGION")
fi

if [[ "$BUNDLE_PROFILE" == "reduced" ]]; then
  if [ -z "$PATH_TO_BOOTSTRAP_ACTION" ] || [ -z "$PATH_TO_EXTRAS" ]; then
    echo >&2 "--path-to-bootstrap-action and --path-to-extras must be scefied"
    exit 1
  fi
  CREATE_CLUSTER_ARGS+=(--bootstrap-actions '[{"Path":"'"$PATH_TO_BOOTSTRAP_ACTION"'","Args":["'"$PATH_TO_EXTRAS"'"],"Name":"lbx-extra"}]')
fi

aws emr create-cluster "$PROFILE" "${CREATE_CLUSTER_ARGS[@]}"

rm -r ".tmp_sc/"
