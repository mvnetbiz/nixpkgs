{ lib
, buildPythonApplication
, fetchFromGitHub

# build deps
, poetry-core

# propagates
, cbor2
, python-dateutil
, pyyaml
, tomlkit
, u-msgpack-python

# tested using
, pytestCheckHook
}:

buildPythonApplication rec {
  pname = "remarshal";
  version = "0.14.0";
  format = "pyproject";

  src = fetchFromGitHub {
    owner = "dbohdan";
    repo = pname;
    rev = "v${version}";
    hash = "sha256:nTM3jrPf0kGE15J+ZXBIt2+NGSW2a6VlZCKj70n5kHM=";
  };

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace "poetry.masonry.api" "poetry.core.masonry.api" \
      --replace 'PyYAML = "^5.3"' 'PyYAML = "*"'
  '';

  nativeBuildInputs = [
    poetry-core
  ];

  propagatedBuildInputs = [
    cbor2
    python-dateutil
    pyyaml
    (tomlkit.overridePythonAttrs (oldAttrs: rec {
      version = "0.7.2";
      src = oldAttrs.src.override {
        inherit version;
        sha256 = "d7a454f319a7e9bd2e249f239168729327e4dd2d27b17dc68be264ad1ce36754";
      };
    }))

    u-msgpack-python
  ];

  checkInputs = [
    pytestCheckHook
  ];

  meta = with lib; {
    description = "Convert between TOML, YAML and JSON";
    license = licenses.mit;
    homepage = "https://github.com/dbohdan/remarshal";
    maintainers = with maintainers; [ offline ];
  };
}
