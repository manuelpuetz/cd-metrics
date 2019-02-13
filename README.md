# CD metrics

Playground for pulling Continuous Delivery metrics from build servers.

## Concourse
### Usage
Install `fly` and log in
```
brew cask install fly
fly --target my-target login --team-name my-concourse-team --concourse-url https://my.concourse.url/
```

After login, `~/.flyrc` contains an authorization token that will be used for the Concourse requests.

Go to the bottom of the ruby script and change it to point at the names of your own pipelines and jobs.

```
BASE_URL=https://my.concourse.url TEAM=my-concourse-team ruby ./go.rb
```

### Concourse API
Routes: https://github.com/concourse/concourse/blob/master/atc/routes.go

Utility script to try out different endpoints (after fly login as described above):
```
./concourse-api my-concourse-team https://my.concourse.url/api/v1/builds/123456/plan
```