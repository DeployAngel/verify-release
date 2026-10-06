# DeployAngel release verification

Registers each deploy with [DeployAngel](https://www.deployangel.com) and waits
for production to clear it. The verdict, failing findings, and new exceptions go
on the job's summary page, and a failed release fails the step. While a release
isn't cleared yet, the summary also lists what to exercise against production
so it clears sooner (`deployangel plan` has the details).

DeployAngel verifies a release from your app's own production telemetry, so
this step goes **after** the deploy, in the job that deploys. There's nothing
to check in a pull request.

```yaml
# .github/workflows/deploy.yml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      # ... your deploy step ...
      - uses: DeployAngel/verify-release@v1
        with:
          api-token: ${{ secrets.DEPLOYANGEL_API_TOKEN }}
```

## Setup

1. Add the DeployAngel agent to your app and deploy it, so DeployAngel gets
   production telemetry: the [deployangel gem](https://github.com/DeployAngel/deployangel-ruby)
   for Rails, or the [deployangel package](https://github.com/DeployAngel/deployangel-python)
   for Django, FastAPI, and Flask.
2. In DeployAngel, open the app's Settings, create a **CI deploys** token, and
   save it as the repository secret `DEPLOYANGEL_API_TOKEN`.
3. Add the step above after your deploy step.

The action runs DeployAngel's command-line tool, which comes with the Ruby gem,
so it needs Ruby 3.1 or later on the runner, for Python apps too. GitHub's
Ubuntu runners have it; elsewhere, add `ruby/setup-ruby` first. The tool is
installed into its own folder and doesn't need Rails or your app, so a Python
project needs nothing else, and a Rails app's bundle isn't touched.

## What fails the step

| The release | The step |
| --- | --- |
| Cleared | Passes |
| Has no problems at the initial check (`wait: initial`) | Passes, with a note that it isn't cleared yet |
| Has warnings at the initial check | Passes, with a warning |
| **Failed** | **Fails** |
| Ended not cleared, such as a release that never reported because it didn't boot | Fails, unless `fail-on-inconclusive: false` |
| Ended not cleared because it was deployed in the app's first day, or a newer release replaced it | Passes, with a note |
| Is still being verified when `timeout` runs out | Passes, with a warning |

A bad token, a network error, or no deployment for the commit fails the step.
The deploy itself has already happened either way: a failed step tells you, it
doesn't roll anything back. Use the outputs to do that yourself.

## Inputs

| Input | Default | |
| --- | --- | --- |
| `api-token` | (required) | A "CI deploys" token. |
| `wait` | `initial` | `initial` returns at the first check, 15 minutes after the release's first telemetry. `verdict` waits until it's cleared, failed, or ends not cleared, which often takes longer. `closed` also waits out scheduled jobs that weren't due yet, up to 8 days. `none` only registers. |
| `timeout` | `30m` | Longest wait, in seconds or with `m` or `h`. |
| `fail-on-inconclusive` | `true` | Fail the step when the release ends not cleared (see above). |
| `register` | `true` | Register the deploy first. Set to `false` if something else registers it, such as a Kamal hook or Heroku. |
| `commit` | the workflow's commit | The deployed commit. |
| `version` | `run-<number>` | A label for the release, such as a tag. |
| `gem-version` | `>= 0.1.11` | Which version of the deployangel gem (the command-line tool) to run, whatever language your app is in. |

Waiting holds the runner for the whole wait, and private repositories pay for
those minutes. `wait: initial` keeps that to about 15 minutes.

## Outputs

| Output | |
| --- | --- |
| `verdict` | `verified`, `failed`, or `inconclusive`; empty while still being verified |
| `verdict-reason` | Why, such as `regression_detected`, `warm_up`, or `no_release_telemetry` |
| `state` | The verification's state, such as `observing` or `closed` |
| `deployment-id` | The deployment's ID in DeployAngel |
| `dashboard-url` | The release's page in DeployAngel |
| `exit-code` | The exit code of `deployangel verify` ([reference](https://www.deployangel.com/docs#cli)) |

For example, to roll back a failed release:

```yaml
      - uses: DeployAngel/verify-release@v1
        id: deployangel
        continue-on-error: true
        with:
          api-token: ${{ secrets.DEPLOYANGEL_API_TOKEN }}
      - if: steps.deployangel.outputs.verdict == 'failed'
        run: ./bin/rollback
```

## Other CI systems

The action wraps the gem's `deployangel` command, which works the same way in
GitLab CI, CircleCI, Buildkite, and anywhere else. See
[Register deploys from CI](https://www.deployangel.com/docs#deploys).

## License

MIT
