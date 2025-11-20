
get all thecredentials i had available in this account 
```
type $Env:USERPROFILE\.aws\credentials
```

```
$Env:AWS_PROFILE="PROFILENAME"
```

check if i can connect to aws 
```
aws sts get-caller-identity --profile PROFILENAME
```

arn for github
github_actions_role_arn = "arn:aws:iam::215982717135:role/github-actions-twin-deploy"















