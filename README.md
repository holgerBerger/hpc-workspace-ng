# hpc-workspace-ng
playground for next next generation of hpc workspace

this is not yet usefull or usable.

## motivation

- major rewrite
- restructure source to make it easyer to understand and maintain
- add a lot more testing
- add a lot more of comments and documentations
- get rid of pre c++11 C++
- get rid of C++ altogether 
- try some new ideas
- prepare for more ideas 

## objectives

- in first step, be compatible to hpc-workspace++
- read old configs and old database
- prepare for new database format, with on-the-fly migration
- clean up some naming mess
- new configuration can be split in several files (easyer to have partially different configs with shared filesystems)
- proper DB abstraction, a future DB could be even a DBMS
- probably integration of more plugins/hooks, also for users
- broad set up funtions to deal with workspace DB and workspace directories, to ease development of new tools

## ideas

- hooks which would allow users to change e.g. permissions as soon as ws_allocate is executed
- admin can define with plugins which of the "spaces" is choosen, based e.g. on user, this helps using e.g. lustre DNE
- a rough idea of "archiving", a workspace could resist in DB but would in fact be on external storage, migration done
  by some "mover"
