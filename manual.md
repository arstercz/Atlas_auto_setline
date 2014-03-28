Atlas_auto_setline
==================

此脚本配合360 Atlas中间件的使用， 检测slave状况(延迟或slavethread错误)，自动上线或下线存在于Atlas admin接口里的slave节点；

 

 - 不对master做改动，仅检测slave信息； 
 - 多个slave不支持，但可以用shell命令替换,详见见 perldoc
   atlas_auto_setline说明。

测试说明:关闭SQL_THREAD:

    [root@tovm scripts]# perl atlas_auto_setline.pl --conf=db.conf --verbose --setline
     +---2014-03-28 17:40:17, 10.0.23.205, Slave_IO_Running: Yes, Slave_SQL_Running: No, Seconds_Behind_Master: NULL
     +-- 2014-03-28 17:40:17 OK SET offline node 10.0.23.201:5011
     +-- 2014-03-28 17:40:17 OK SET offline node 10.0.23.201:5012
     +-- 2014-03-28 17:40:17 OK SET offline node 10.0.23.201:5013

下线所有Atlas的slave节点(多个实例做多次操作):

    mysql> select * from backends;
    +-------------+------------------+---------+------+
    | backend_ndx | address          | state   | type |
    +-------------+------------------+---------+------+
    |           1 | 10.0.23.200:3306 | up      | rw   |
    |           2 | 10.0.23.200:3306 | up      | ro   |
    |           3 | 10.0.23.205:3306 | offline | ro   |
    +-------------+------------------+---------+------+
    ...

启动SQL_THREAD:
   

    [root@tovm scripts]# perl atlas_auto_setline.pl --conf=db.conf --verbose --setline
         +---2014-03-28 17:40:47, 10.0.23.205, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
         +-- 2014-03-28 17:40:47 OK SET online node 10.0.23.201:5011
         +-- 2014-03-28 17:40:47 OK SET online node 10.0.23.201:5012
         +-- 2014-03-28 17:40:47 OK SET online node 10.0.23.201:5013
     
上线所有Atlas的slave节点(多个实例多次操作):

    mysql> select * from backends;
    +-------------+------------------+-------+------+
    | backend_ndx | address          | state | type |
    +-------------+------------------+-------+------+
    |           1 | 10.0.23.200:3306 | up    | rw   |
    |           2 | 10.0.23.200:3306 | up    | ro   |
    |           3 | 10.0.23.205:3306 | up    | ro   |
    +-------------+------------------+-------+------+

手工offline一个节点:

    mysql> set offline 3;         
    +-------------+------------------+---------+------+
    | backend_ndx | address          | state   | type |
    +-------------+------------------+---------+------+
    |           3 | 10.0.23.205:3306 | offline | ro   |
    +-------------+------------------+---------+------+

1 row in set (0.00 sec)

    [root@tovm scripts]# perl atlas_auto_setline.pl --conf=db.conf --verbose --setline
     +---2014-03-28 17:35:50, 10.0.23.205, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
     +-- 2014-03-28 17:35:50 OK SET online node 10.0.23.201:5011

上线成功:

    mysql> select * from backends;
    +-------------+------------------+---------+------+
    | backend_ndx | address          | state   | type |
    +-------------+------------------+---------+------+
    |           1 | 10.0.23.200:3306 | up      | rw   |
    |           2 | 10.0.23.200:3306 | up      | ro   |
    |           3 | 10.0.23.205:3306 | offline | ro   |
    +-------------+------------------+---------+------+
    3 rows in set (0.00 sec)

