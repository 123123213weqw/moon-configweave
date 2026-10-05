# Request and result guide

Every example below is an executable fixture. Assertions cover the listed result fields; additional output fields are documented by the API and other fixtures. Error cases intentionally reject the request.

## layer merge

```json
{
  "layers": [
    {
      "name": "base",
      "value": {
        "db": {
          "host": "local",
          "port": 1
        }
      }
    },
    {
      "name": "prod",
      "value": {
        "db": {
          "port": 2
        }
      }
    }
  ]
}
```

Expected result fields:

```json
{
  "config/db/host": "local",
  "config/db/port": 2,
  "origins//db/port": [
    "base",
    "prod"
  ]
}
```

## interpolation keeps type

```json
{
  "layers": [
    {
      "name": "x",
      "value": {
        "n": 3,
        "copy": "${config:/n}",
        "message": "n=${config:/n}"
      }
    }
  ]
}
```

Expected result fields:

```json
{
  "config/copy": 3,
  "config/message": "n=3"
}
```

## secret aliases

```json
{
  "layers": [
    {
      "name": "x",
      "value": {
        "db": {
          "password": "${env:KEY}"
        },
        "alias": "${config:/db}"
      }
    }
  ],
  "env": {
    "KEY": "secret"
  },
  "secret_env": [
    "KEY"
  ]
}
```

Expected result fields:

```json
{
  "config/db/password": "***",
  "config/alias": "***"
}
```

## unique arrays

```json
{
  "layers": [
    {
      "name": "a",
      "value": {
        "x": [
          1,
          2
        ]
      }
    },
    {
      "name": "b",
      "value": {
        "x": [
          2,
          3
        ]
      }
    }
  ],
  "arrays": "unique"
}
```

Expected result fields:

```json
{
  "config/x": [
    1,
    2,
    3
  ]
}
```

## missing env

```json
{
  "layers": [
    {
      "name": "x",
      "value": {
        "a": "${env:MISSING}"
      }
    }
  ]
}
```

Expected: nonzero exit with an input error.

## cycle

```json
{
  "layers": [
    {
      "name": "x",
      "value": {
        "a": "${config:/b}",
        "b": "${config:/a}"
      }
    }
  ]
}
```

Expected: nonzero exit with an input error.

## type conflict

```json
{
  "layers": [
    {
      "name": "a",
      "value": {
        "x": 1
      }
    },
    {
      "name": "b",
      "value": {
        "x": "a"
      }
    }
  ],
  "strict_types": true
}
```

Expected: nonzero exit with an input error.

## numeric constraint wrong type

```json
{
  "layers": [
    {
      "name": "a",
      "value": {
        "x": "text"
      }
    }
  ],
  "constraints": [
    {
      "path": "/x",
      "min": 1
    }
  ]
}
```

Expected result fields:

```json
{
  "valid": false
}
```

## Host adapter

```sh
python -B scripts/files.py MANIFEST.json
```

Read the current boundaries before using this adapter.
