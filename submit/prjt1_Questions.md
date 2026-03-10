Questions



**Technical Challenges** Describe the greatest challenge(s) you encountered in translating the template from CloudFormation to Terraform. (1-2 paragraphs)

I am not familiar with terraform code. The biggest struggle was confirming that the code was formatted correctly. Additionally AWS does not .tf files.





**Access Permissions** What element (specify file and line #) grants the SNS subscription permission to send messages to your API? Locate and explain your answer.

security group allows inbound traffic on port 8000.

SNSTopicPolicy statements also allows ANA talk to API. 

The statement allows messages to be sent from the SNS to the API, however in order for the API to receive this the security group must allow communications between these two elements.







**Event flow and reliability:** Trace the path of a single CSV file from the moment it is uploaded to raw/ in S3 until the FastAPI app processes it. What happens if the EC2 instance is down or the /notify endpoint returns an error? How does SNS behave (e.g., retries, dead-letter behavior), and what would you change if this needed to be production-grade?



The s3 bucket notices that an object was created s3:ObjectCreated, then publishes a sns packet in ds5220-dp1, which resets a post request to the /notify endpoint, then fastapi parses the s3 bucet and downloads the file.

If there is a complication, EC2 is down. endpoint returns an error. The SNS will attempt a few more times before exiting and the /notify returns the errors. If this ended to be production-grade we could add a queue so that if a message is not delivered it rests in the queue until the EC2 application is online again. This would help to not lose data.



**IAM and least privilege:** The IAM policy for the EC2 instance grants full access to one S3 bucket. List the specific S3 operations the application actually performs (e.g., GetObject, PutObject, ListBucket). Could you replace the “full access” policy with a minimal set of permissions that still allows the app to work? What would that policy look like?

sGetObject - to download csv, PutObject to upload the updated baseline.json, ListBucket to check is baseline/ other folder exists, DeleteObject , GetBucketLocation.

We could replace the Full access to only the specific actions that we want the user to be able to use. This would include putting only the desired actions int he statement for the s3bucketaccesspolicy



**Architecture and scaling:** This solution uses batch-file events (S3 + SNS) to drive processing, with a rolling statistical baseline in memory and in S3. How would the design change if you needed to handle 100x more CSV files per hour, or if multiple EC2 instances were processing files from the same bucket? Address consistency of the shared baseline.json, concurrent processing, and any tradeoffs.



If we had to handle more csv's it could get complicated because the latest baseline.json would always overwrite any previous change (think about pushing the same change seconds of another in which the first pushed is invalid). Additionally our EC2 instance could be overwhelmed with the number of requests and timeout. Instead we could use a dynamic database in order to combat this, however it would be a more complex and costly system. On AWS, we could use DynamoDB in order to achieve this.

