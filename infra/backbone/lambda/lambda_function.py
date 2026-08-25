import boto3
import json
import os
from datetime import datetime, timezone

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
table = dynamodb.Table('complyflow-status')
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']

def lambda_handler(event, context):
    for record in event['Records']:
        body = json.loads(record['body'])
        for s3_record in body.get('Records', []):
            bucket = s3_record['s3']['bucket']['name']
            key = s3_record['s3']['object']['key']
            file_id = key.split('/')[-1]

            # Write "processing" status
            table.put_item(Item={
                'fileId': file_id,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'status': 'processing',
                'bucket': bucket,
                'key': key
            })

            # --- stub compliance check / metadata extraction goes here ---
            result_status = 'complete'  # or 'failed', based on your check

            table.put_item(Item={
                'fileId': file_id,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'status': result_status,
                'bucket': bucket,
                'key': key
            })

            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject=f'ComplyFlow: {file_id} {result_status}',
                Message=json.dumps({'fileId': file_id, 'status': result_status})
            )

    return {'statusCode': 200}