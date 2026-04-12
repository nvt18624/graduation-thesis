import boto3
import json
import os


def handler(event, context):
    app        = event["app"]
    prefix     = os.environ["PREFIX"]
    region     = os.environ["REGION"]
    account_id = os.environ["ACCOUNT_ID"]

    ssm = boto3.client("ssm", region_name=region)
    ec2 = boto3.client("ec2", region_name=region)

    # Read stable tag + port from SSM Parameter Store
    result  = ssm.get_parameters(Names=[
        f"/{prefix}/{app}/stable-tag",
        f"/{prefix}/{app}/port",
    ])
    by_name = {p["Name"]: p["Value"] for p in result["Parameters"]}

    if f"/{prefix}/{app}/stable-tag" not in by_name:
        return {"statusCode": 404, "body": f"No stable-tag found for app {app}. Has a successful deploy happened yet?"}

    stable_tag = by_name[f"/{prefix}/{app}/stable-tag"]
    port       = by_name[f"/{prefix}/{app}/port"]

    registry = f"{account_id}.dkr.ecr.{region}.amazonaws.com"
    image    = f"{registry}/{prefix}-{app}:{stable_tag}"

    # Find running EC2 instance by App tag
    resp = ec2.describe_instances(Filters=[
        {"Name": "tag:App",             "Values": [app]},
        {"Name": "instance-state-name", "Values": ["running"]},
    ])
    instance_ids = [
        i["InstanceId"]
        for r in resp["Reservations"]
        for i in r["Instances"]
    ]
    if not instance_ids:
        return {"statusCode": 404, "body": f"No running instance found for app {app}"}

    cmd = ssm.send_command(
        InstanceIds=instance_ids,
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": [
            f"REGISTRY={registry}",
            f"IMAGE={image}",
            f"aws ecr get-login-password --region {region} | docker login --username AWS --password-stdin $REGISTRY",
            "docker pull $IMAGE",
            f"docker stop {app} 2>/dev/null || true",
            f"docker rm   {app} 2>/dev/null || true",
            f"docker run -d --name {app} --restart unless-stopped -p {port}:{port} $IMAGE",
            f"echo Rollback {app} to {stable_tag} done",
        ]},
        Comment=f"AI rollback {app} to {stable_tag}",
    )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "app":        app,
            "stable_tag": stable_tag,
            "command_id": cmd["Command"]["CommandId"],
            "instances":  instance_ids,
        }),
    }
