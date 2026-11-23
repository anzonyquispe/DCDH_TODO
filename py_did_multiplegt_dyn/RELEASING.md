# Releasing to PyPI

The package is published through GitHub Actions and PyPI Trusted Publishing.
Do not upload the files in `dist/` manually unless the automated workflow is
unavailable.

## One-time PyPI configuration

Open the existing PyPI project's **Publishing** settings and add a GitHub
Actions Trusted Publisher with these exact values:

<https://pypi.org/manage/project/py-did-multiplegt-dyn/settings/publishing/>

- GitHub owner: `Credible-Answers`
- GitHub repository: `py_did_multiplegt_dyn`
- Workflow: `publish.yml`
- Environment: `pypi`

The GitHub repository must also have an environment named `pypi`. Optional
reviewer protection can be enabled on that environment.

## Release checklist

1. Confirm `pyproject.toml` and `CHANGELOG.md` contain the intended version.
2. Run the full test suite and build validation locally.
3. Commit the release changes to `main` and push them to GitHub.
4. Create and push a tag matching the package version exactly:

   ```bash
   git tag -a v0.1.8 -m "Release 0.1.8"
   git push origin main
   git push origin v0.1.8
   ```

5. On GitHub, create a release from tag `v0.1.8`, copy the `0.1.8` section of
   `CHANGELOG.md` into the release notes, and publish the release.
6. Watch the **Publish to PyPI** workflow. It will:

   - test Python 3.8 and 3.12;
   - reject a tag that does not match package metadata;
   - build the wheel and source distribution;
   - validate both artifacts with Twine;
   - publish through the protected `pypi` environment.

7. Confirm the new version on PyPI and test it in a fresh environment:

   ```bash
   python -m pip install --no-cache-dir py-did-multiplegt-dyn==0.1.8
   python -c "from did_multiplegt_dyn import DidMultiplegtDyn; print(DidMultiplegtDyn)"
   ```
