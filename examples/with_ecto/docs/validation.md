# Validation

Requests are validated twice:

1. the parameters are cast into the types of the action spec, answering
   `422` when they do not match
2. the data is validated by an Ecto changeset, answering `422` with the
   errors of each field
