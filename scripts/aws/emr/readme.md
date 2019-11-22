### create-emr-cluster.sh

1. Install AWS CLI https://docs.aws.amazon.com/cli/latest/userguide/install-cliv1.html

2. Install JQ https://stedolan.github.io/jq/download/

3. Create own ssh key in AWS Console https://us-west-2.console.aws.amazon.com/ec2/v2/home?region=us-west-2#KeyPairs:sort=keyName

4. Download `create-emr-cluster.sh`

5. For the default setup use the following script:

```shell script
export AWS_ACCESS_KEY_ID=<AWS S3 ACCESS KEY>
export AWS_SECRET_ACCESS_KEY=<AWS S3 SECRET KEY>

sh create-emr-cluster.sh \
    --region us-west-2 \
    --ssh-key <NAME OF TH SSH KEY CREATE ON STEP 3> \
    --path-to-config <PATH TO CLUSTER CONFIG>
```