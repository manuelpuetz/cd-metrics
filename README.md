# CD metrics

Playground for pulling Continuous Delivery metrics from build servers.

## Concourse
### Usage
Install `fly` and log in
```
brew cask install fly
fly --target nh login --team-name nh --concourse-url https://my.concourse.url/
```

After login, `~/.flyrc` contains an authorization token that will be used for the Concourse requests.

Go to the bottom of the ruby script and change it to point at the names of your own pipelines and jobs.

```
BASE_URL=https://my.concourse.url ruby ./go.rb
```

### Concourse API
Routes: https://github.com/concourse/concourse/blob/master/atc/routes.go
