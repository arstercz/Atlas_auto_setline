Atlas_auto_setline
==================

a tool for automatic offline/online unusable slave node in Atlas open source software

此脚本配合360 Atlas中间件的使用， 检测slave状况(延迟或slavethread错误)，自动上线或下线存在于Atlas admin接口里的slave节点；


 - 不对master做改动，仅检测slave信息； 
 - 支持多个slave, 详见 perldoc atlas_auto_setline说明;
 - 多个atlas端口必须是同一实例下的;
 - 新加循环检测, 默认每10s检测一次, 在上下线过程中忽略kill的INT和TERM两个信号;


需要的依赖见 SYSTEM REQUIREMENTS 说明(perldoc atlas_auto_setline.pl)

db.conf文件配置(单实例下的多个库)举例,:

    #slave host and atlas admin host info.
    slave_host:172.30.0.15,172.30.0.16     #多台slave以','分隔
    slave_port:3306                        #slave 服务端口
    slave_user:slave_user                  #可以检测slave 延迟状态的用户
    slave_pass:xxxxxx                      #slave_user口令   
    atlas_host:172.30.0.18                 #atlas对外服务的ip, 建议是虚ip
    atlas_port:5012                        #atlas对外服务的端口, 一个atlas的mysql-proxyd占用一个端口, 如果起了多个, 以','分隔指定多个端口
    atlas_user:admin                       #atlas的账户
    atlas_pass:xxxxxxx                     #atlas账户的口令信息


可添加到任务计划循环检测, 如下:

   #!/bin/bash
   (
      flock -x -n 200
      if [[ $? -ne 0 ]]; then
        echo "Failed acquiring lock"
        exit 1
      fi
      perl atlas_auto_setline.pl --conf=db.conf --verbose --setline --interval=10 >>setline.log 2>&1
    ) 200>/web/scripts/atlas_auto/atlas.lock

测试说明:
关闭SQL_THREAD:
==============

    mysql> select * from backends;
    +-------------+-------------------+-------+------+
    | backend_ndx | address           | state | type |
    +-------------+-------------------+-------+------+
    |           1 | 172.30.0.14:3306 | up    | rw   |
    |           2 | 172.30.0.14:3306 | up    | ro   |
    |           3 | 172.30.0.15:3306 | up    | ro   |
    |           4 | 172.30.0.16:3306 | up    | ro   |
    +-------------+-------------------+-------+------+
    4 rows in set (0.00 sec)


停止ip为16的slave的复制线程后(多个端口，多个offline操作):

    [root@tovm scripts]# perl atlas_auto_setline.pl --conf=db.conf --verbose --setline --threshold=30
     +---2014-04-15 11:53:01, 172.30.0.15, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 13
     +---2014-04-15 11:53:01, 172.30.0.16, Slave_IO_Running: No, Slave_SQL_Running: No, Seconds_Behind_Master: NULL
     +-- 2014-04-15 11:53:01 OK SET offline node 172.30.0.16:5012

atlas下线:

     mysql> select * from backends;
     +-------------+-------------------+-------+------+
     | backend_ndx | address           | state | type |
     +-------------+-------------------+-------+------+
     |           1 | 172.30.0.14:3306 | up     | rw   |   
     |           2 | 172.30.0.14:3306 | up     | ro   |   
     |           3 | 172.30.0.15:3306 | up     | ro   |   
     |           4 | 172.30.0.16:3306 | offline| ro   |   
     +-------------+-------------------+-------+------+
     4 rows in set (0.00 sec)


启动SQL_THREAD:

    [root@tovm scripts]# perl atlas_auto_setline.pl --conf=db.conf --verbose --setline --threshold=30
     +---2014-04-15 11:54:01, 172.30.0.15, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
     +---2014-04-15 11:54:01, 172.30.0.16, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
     +-- 2014-04-15 11:54:01 OK SET online node 172.30.0.16:5012



手工offline一个节点:
===================

    mysql> set offline 4;         
    +-------------+------------------+---------+------+
    | backend_ndx | address          | state   | type |
    +-------------+------------------+---------+------+
    |           3 | 172.30.0.16:3306 | offline | ro   |
    +-------------+------------------+---------+------+

1 row in set (0.00 sec)


     mysql> select * from backends;
     +-------------+-------------------+-------+------+
     | backend_ndx | address           | state | type |
     +-------------+-------------------+-------+------+
     |           1 | 172.30.0.14:3306 | up     | rw   |   
     |           2 | 172.30.0.14:3306 | up     | ro   |   
     |           3 | 172.30.0.15:3306 | up     | ro   |   
     |           4 | 172.30.0.16:3306 | offline| ro   |   
     +-------------+-------------------+-------+------+
     4 rows in set (0.00 sec)

运行脚本使其上线:

    [root@tovm scripts]# perl atlas_auto_setline.pl --conf=db.conf --verbose --setline --threshold=30
     +---2014-04-15 11:56:01, 172.30.0.15, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
     +---2014-04-15 11:56:01, 172.30.0.16, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
     +-- 2014-04-15 11:56:01 OK SET online node 172.30.0.16:5012

上线成功:

无限循环检测
=================

    [root@tovm scripts]# perl atlas_auto_setline.pl --conf=db.conf --verbose --setline --threshold=30 --interval=10
     +---2014-09-22 16:22:42, 172.30.0.154, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
     +---2014-09-22 16:22:42, 172.30.0.133, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
     +---2014-09-22 16:22:52, 172.30.0.154, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
     +---2014-09-22 16:22:52, 172.30.0.133, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
     +---2014-09-22 16:23:02, 172.30.0.154, Slave_IO_Running: No, Slave_SQL_Running: No, Seconds_Behind_Master: NULL
     +-- 2014-09-22 16:23:02 OK SET offline node 172.30.0.154:5012
     +---2014-09-22 16:23:02, 172.30.0.133, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
     +---2014-09-22 16:23:12, 172.30.0.154, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
     +-- 2014-09-22 16:23:12 OK SET online node 172.30.0.154:5012
     +---2014-09-22 16:23:12, 172.30.0.133, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
     +---2014-09-22 16:23:22, 172.30.0.154, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
     +---2014-09-22 16:23:22, 172.30.0.133, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
     +---2014-09-22 16:23:32, 172.30.0.154, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
