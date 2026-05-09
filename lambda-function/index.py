import boto3
import json
import os
from datetime import datetime

# ECS client initialization
ecs_client = boto3.client('ecs', region_name=os.environ.get('AWS_REGION', 'ap-northeast-1'))


def lambda_handler(event, context):
    """
    EventBridge triggered Lambda function that launches Fargate tasks.
    This function is called periodically (default: every hour) by EventBridge.

    Environment variables:
    - AWS_REGION: AWS region (default: ap-northeast-1)
    - ECS_CLUSTER: ECS cluster name (default: playwright-cloud-executer-cluster)
    - TASK_DEFINITION: ECS task definition (default: playwright-cloud-executer:1)
    - SUBNET_ID: VPC subnet ID for Fargate task
    - SECURITY_GROUP_ID: Security group ID for Fargate task
    """
    try:
        # Get configuration from environment variables
        cluster = os.environ.get('ECS_CLUSTER', 'playwright-cloud-executer-cluster')
        task_definition = os.environ.get('TASK_DEFINITION', 'playwright-cloud-executer:1')
        subnet_id = os.environ.get('SUBNET_ID')
        security_group_id = os.environ.get('SECURITY_GROUP_ID')
        site_name = event.get('site_name', 'yahoo')
        aws_region = os.environ.get('AWS_REGION', 'ap-northeast-1')

        # Validation
        if not subnet_id or not security_group_id:
            error_msg = 'Missing required environment variables: SUBNET_ID or SECURITY_GROUP_ID'
            print(f'ERROR: {error_msg}')
            return {
                'statusCode': 400,
                'body': json.dumps({'error': error_msg})
            }

        print(f'[INFO] Starting Fargate task')
        print(f'  Cluster: {cluster}')
        print(f'  Task Definition: {task_definition}')
        print(f'  Site Name: {site_name}')
        print(f'  Region: {aws_region}')

        # Launch Fargate task
        response = ecs_client.run_task(
            cluster=cluster,
            taskDefinition=task_definition,
            launchType='FARGATE',
            networkConfiguration={
                'awsvpcConfiguration': {
                    'subnets': [subnet_id],
                    'securityGroups': [security_group_id],
                    'assignPublicIp': 'ENABLED'
                }
            },
            overrides={
                'containerOverrides': [
                    {
                        'name': 'playwright-container',
                        'environment': [
                            {'name': 'SITE_NAME', 'value': site_name},
                            {'name': 'AWS_REGION', 'value': aws_region}
                        ]
                    }
                ]
            }
        )

        # Extract task ARN from response
        if not response.get('tasks') or len(response['tasks']) == 0:
            error_msg = 'No tasks were launched'
            print(f'ERROR: {error_msg}')
            return {
                'statusCode': 500,
                'body': json.dumps({'error': error_msg})
            }

        task_arn = response['tasks'][0]['taskArn']
        print(f'[SUCCESS] Task launched: {task_arn}')

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Fargate task started successfully',
                'taskArn': task_arn,
                'timestamp': datetime.utcnow().isoformat(),
                'site': site_name
            })
        }

    except Exception as e:
        error_msg = f'Error launching Fargate task: {str(e)}'
        print(f'ERROR: {error_msg}')
        print(f'Exception: {type(e).__name__}')
        return 