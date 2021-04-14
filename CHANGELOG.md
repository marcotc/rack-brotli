# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.1.0
## Changed
- Removed dependency on `git-version-bump` gem for versioning. `rack-brotli` now only depends on `rack` and `brotli`.

## 1.0.0
## Changed
- Default compression quality reduced from `maximum` to `5`.
  - This should provide slightly faster compression speeds compared to GZip level 6, with slightly smaller output size.

