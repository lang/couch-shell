couch-shell is a basic shell to interact with a CouchDB server.

Install with rubygems:

  $ sudo gem install couch-shell

Only tested with Ruby 1.9!

Example session:

  $ couch-shell 127.0.0.1:5984
  couch-shell 0.0.8
  Set server to http://127.0.0.1:5984
  GET / 200 OK   vars: r0, j0
  {
    "couchdb": "Welcome",
    "version": "1.0.1"
  }
  >> cput contacts
  PUT /contacts 201 Created   vars: r1, j1
  {
    "ok": true
  }
  GET /contacts 200 OK   vars: r2, j2
  body has 213 bytes
  contacts >> post {"name":"Jim", "email":"jim@example.com"}
  POST /contacts 201 Created   vars: r3, j3
  {
    "ok": true,
    "id": "37425dfe6340ac376572f5042f000de1",
    "rev": "1-aefa5e0e3de5ac4fcc0e28b725f1d898"
  }
  contacts >> cd $(id)
  contacts/37425dfe6340ac376572f5042f000de1 >> get
  GET /contacts/37425dfe6340ac376572f5042f000de1 200 OK   vars: r4, j4
  {
    "_id": "37425dfe6340ac376572f5042f000de1",
    "_rev": "1-aefa5e0e3de5ac4fcc0e28b725f1d898",
    "name": "Jim",
    "email": "jim@example.com"
  }
  contacts/37425dfe6340ac376572f5042f000de1 >> member name "Jim Thompson"
  PUT /contacts/37425dfe6340ac376572f5042f000de1/?rev=1-aefa5e0e3de5ac4fcc0e28b725f1d898 201 Created   vars: r5, j5
  {
    "ok": true,
    "id": "37425dfe6340ac376572f5042f000de1",
    "rev": "2-6640ecdc0102456c7b924768e5bbc4c1"
  }
  contacts/37425dfe6340ac376572f5042f000de1 >> get
  GET /contacts/37425dfe6340ac376572f5042f000de1 200 OK   vars: r6, j6
  {
    "_id": "37425dfe6340ac376572f5042f000de1",
    "_rev": "2-6640ecdc0102456c7b924768e5bbc4c1",
    "name": "Jim Thompson",
    "email": "jim@example.com"
  }
  contacts/37425dfe6340ac376572f5042f000de1 >> exit
  bye
