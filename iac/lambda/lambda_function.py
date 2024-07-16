import os
import json
import boto3
from botocore.exceptions import ClientError


table_name = os.getenv('VISITOR_TABLE')
dynamo_table = boto3.resource('dynamodb', region_name='us-east-1').Table(table_name)
id_value = 'visitors'


def lambda_handler(event, context):
    response = None
    try:
        http_method = event.get('httpMethod')
        path = event.get('path')

        if http_method == 'GET' and path == '/visitor':
            response = update_visitor_count()
            response = get_visitor_count()
            
        else:
            response = build_response(404, '404 not found')
            
    except Exception as e:
        print('Error:', e)
        response = build_response(400, 'Error processing request')

    return response
  
    
def get_visitor_count():
    try:
        response = dynamo_table.get_item(Key={'id': id_value})
        response['Item']['count_visitors'] = str(response['Item']['count_visitors'])
        return build_response(200, response.get('Item').get('count_visitors'))
        
    except ClientError as e:
        print('Error:', e)


def update_visitor_count():
    try:
        response = dynamo_table.update_item (
            Key={'id': id_value},
            UpdateExpression='SET count_visitors = count_visitors + :inc',
            ExpressionAttributeValues={':inc': 1}
            )
            
        body = {
            'Operation': 'UPDATE',
            'Message': 'SUCCESS',
            'UpdatedAttributes': response
        }
        return build_response(200, body)
        
        
    except Exception as e:
        print('Not updated: ', e)
  
    
def build_response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Origin': 'https://www.thepott.dev',
            'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
        },
        'body': json.dumps(body)
    }