# Example code to show how IAM policies work

## Prerequisities

* terraform
* ```terraform init```

## Scenario #1: Identity policy allows access

* ```terraform apply```

There is an object in an S3 bucket and a user. The user has access to the object through the identity policy:

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "s3:GetObject"
            ],
            "Effect": "Allow",
            "Resource": "<bucket>/text.txt"
        }
    ]
}
```

```
AWS_ACCESS_KEY_ID=$(terraform output user1_access_key_id) AWS_SECRET_ACCESS_KEY=$(terraform output user1_secret_access_key) AWS_SESSION_TOKEN="" aws s3api get-object --bucket $(terraform output bucket) --key $(terraform output key) >(cat)
```

Returns:

```
Hello world!{
    "AcceptRanges": "bytes",
    "LastModified": "2020-09-24T07:36:36+00:00",
    "ContentLength": 12,
    "ETag": "\"86fb269d190d2c85f6e0468ceca42a20\"",
    "ContentType": "binary/octet-stream",
    "Metadata": {}
}
```

## Scenario #2: A resource policy denies access

* ```terraform apply -var="block_not_user2=true"```

The bucket has a policy that denies access for everybody except ```user2```:

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Deny",
            "NotPrincipal": {
                "AWS": "<iam>/user2-4bc824f880b3df28"
            },
            "Action": "s3:GetObject",
            "Resource": "<bucket>/text.txt"
        }
    ]
}
```

Now user1 can not access the object anymore:

```
AWS_ACCESS_KEY_ID=$(terraform output user1_access_key_id) AWS_SECRET_ACCESS_KEY=$(terraform output user1_secret_access_key) AWS_SESSION_TOKEN="" aws s3api get-object --bucket $(terraform output bucket) --key $(terraform output key) >(cat)
```

```
An error occurred (AccessDenied) when calling the GetObject operation: Access Denied
```

And user2 also can not access it, as there is no Allow policy:

```
AWS_ACCESS_KEY_ID=$(terraform output user2_access_key_id) AWS_SECRET_ACCESS_KEY=$(terraform output user2_secret_access_key) AWS_SESSION_TOKEN="" aws s3api get-object --bucket $(terraform output bucket) --key $(terraform output key) >(cat)
```

```
An error occurred (AccessDenied) when calling the GetObject operation: Access Denied
```

## Scenario #3: The bucket policy gives access to the object

* ```terraform apply -var="block_not_user2=true" -var="allow_user2=true"```

Now the bucket policy allows user2 to access the object. Even without a policy attached to the user the operation is allowed:

```
{
    "Sid": "",
    "Effect": "Allow",
    "Principal": {
        "AWS": "<iam>/user2-4bc824f880b3df28"
    },
    "Action": "s3:GetObject",
    "Resource": "<bucket>/text.txt"
}
```

```
AWS_ACCESS_KEY_ID=$(terraform output user2_access_key_id) AWS_SECRET_ACCESS_KEY=$(terraform output user2_secret_access_key) AWS_SESSION_TOKEN="" aws s3api get-object --bucket $(terraform output bucket) --key $(terraform output key) >(cat)
```

```
Hello world!{
    "AcceptRanges": "bytes",
    "LastModified": "2020-09-24T07:36:36+00:00",
    "ContentLength": 12,
    "ETag": "\"86fb269d190d2c85f6e0468ceca42a20\"",
    "ContentType": "binary/octet-stream",
    "Metadata": {}
}
```

## Scenario #4: Use a condition to give access based on tags

User2 has a policy that allows access to objects tagged with access=secret.

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "s3:GetObject"
            ],
            "Effect": "Allow",
            "Resource": "<bucket>/*",
            "Condition": {
                "StringEquals": {
                    "s3:ExistingObjectTag/access": "secret"
                }
            }
        }
    ]
}
```

The ```tagged_key``` object is tagged with access=secret, so user2 can access it:

```
AWS_ACCESS_KEY_ID=$(terraform output user2_access_key_id) AWS_SECRET_ACCESS_KEY=$(terraform output user2_secret_access_key) AWS_SESSION_TOKEN="" aws s3api get-object --bucket $(terraform output bucket) --key $(terraform output tagged_key) >(cat)
```

But the ```tagged_key2``` object is tagged with access=restricted, so user2 has no access:

```
AWS_ACCESS_KEY_ID=$(terraform output user2_access_key_id) AWS_SECRET_ACCESS_KEY=$(terraform output user2_secret_access_key) AWS_SESSION_TOKEN="" aws s3api get-object --bucket $(terraform output bucket) --key $(terraform output tagged_key2) >(cat)
```

```
An error occurred (AccessDenied) when calling the GetObject operation: Access Denied
```

## Scenario #4: Using a group to allow access to object tagged with the same access as the principal

User1 is a member of a group. The group's policy allows accessing objects that are tagged the same as the principal:

```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetObject"
      ],
      "Effect": "Allow",
      "Resource": "<bucket>/*",
      "Condition": {
        "StringEquals": {
          "s3:ExistingObjectTag/access": "${aws:PrincipalTag/access}"
        }
      }
    }
  ]
}
```

User1 is tagged with access=restricted, so it can access the object with the same tag:

```
AWS_ACCESS_KEY_ID=$(terraform output user1_access_key_id) AWS_SECRET_ACCESS_KEY=$(terraform output user1_secret_access_key) AWS_SESSION_TOKEN="" aws s3api get-object --bucket $(terraform output bucket) --key $(terraform output tagged_key2) >(cat)
```

But has no access to the object tagged with access=secret:

```
AWS_ACCESS_KEY_ID=$(terraform output user1_access_key_id) AWS_SECRET_ACCESS_KEY=$(terraform output user1_secret_access_key) AWS_SESSION_TOKEN="" aws s3api get-object --bucket $(terraform output bucket) --key $(terraform output tagged_key) >(cat)
```

```
An error occurred (AccessDenied) when calling the GetObject operation: Access Denied
```

## Cleanup

* ```terraform destroy```
