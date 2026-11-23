# Publish `did-multiplegt-stat` 0.1.1

## Before creating the GitHub release

1. Commit the package changes, including the `0.1.1` version in
   `pyproject.toml`, and push them to the `main` branch.
2. Open the repository's **Actions** tab and confirm that CI for the `main`
   branch has passed.

## Create the release on GitHub.com

1. Open <https://github.com/Credible-Answers/py_did_multiplegt_stat>.
2. Select **Releases**, then **Create a new release**.
3. In **Choose a tag**, enter `v0.1.1`.
4. Select **Create new tag: v0.1.1 on publish** and use `main` as the target.
5. Set the title to `v0.1.1`.
6. Add release notes, for example:

   > Fix Stata no-extrapolation placebo parity; add scikit-learn,
   > Stata-faithful, and random-forest README examples.

7. Click **Publish release**.

## Confirm publication

1. Go to the **Actions** tab. The **Release** workflow should run `build` and
   `Publish to PyPI`.
2. If GitHub requests approval for the `pypi` environment, approve it.
3. Wait for both jobs to finish successfully.
4. Confirm version `0.1.1` at
   <https://pypi.org/project/did-multiplegt-stat/>.
5. Install-test the published package:

   ```bash
   pip install --upgrade did-multiplegt-stat
   ```
