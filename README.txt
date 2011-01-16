couch-shell is a basic shell to interact with a CouchDB server.

Use `ruby -I lib bin/couch-shell SERVER_URL' to start from a repository
checkout.

Example session:

  $ ruby19 -I lib bin/couch-shell http://mambofulani.couchone.com/
  couch-shell 0.0.1
  Set server to http://mambofulani.couchone.com:80/
  GET / 200 OK
  {"couchdb":"Welcome","version":"1.0.1"}
  >> get couch_planet
  GET /couch_planet 200 OK
  {"db_name":"couch_planet","doc_count":341,"doc_del_count":300,"update_seq":1003,"purge_seq":0,"compact_running":false,"disk_size":2351205,"instance_start_time":"1293666733838699","disk_format_version":5,"committed_update_seq":1003}
  >> exit
  bye
