Atlas_auto_setline
==================

a tool for automatic offline/online unusable slave node in Atlas open source software

此脚本配合360 Atlas中间件的使用， 检测slave状况(延迟或slavethread错误)，自动上线或下线存在于Atlas admin接口里的slave节点；


 - 不对master做改动，仅检测slave信息； 
 - 支持多个slave, 详见 perldoc atlas_auto_setline说明;
 - 多个atlas端口必须是同一实例下的;
 - 新加循环检测, 默认每10s检测一次, 在上下线过程中忽略kill的INT和TERM两个信号;


需要安装的依赖:
```
DBI
DBD::mysql
Config::Auto
```

db.conf文件配置(单实例下的多个库)举例,:
```
#slave host and atlas admin host info.
slave_host:172.30.0.15,172.30.0.16     #多台slave以','分隔
slave_port:3306                        #slave 服务端口
slave_user:slave_user                  #可以检测slave 延迟状态的用户
slave_pass:xxxxxx                      #slave_user口令   
atlas_host:172.30.0.18                 #atlas对外服务的ip, 建议是虚ip
atlas_port:5012                        #atlas对外服务的管理端口, 一个atlas的mysql-proxyd占用一个端口, 如果起了多个, 以','分隔指定多个端口
atlas_user:admin                       #atlas的管理账户
atlas_pass:xxxxxxx                     #atlas管理账户的口令信息
mail:chenzhe07@gmail.com
```
atlas_port和atlas_user和atlas_pass三个参数应该指定atlas的管理端口和管理的用户信息， 用于读取 atlas 的后端状态backend.

可添加到任务计划循环检测, 如下:

```
#!/bin/bash
(
   flock -x -n 200
   if [[ $? -ne 0 ]]; then
     echo "Failed acquiring lock"
     exit 1
   fi
   perl atlas_auto_setline.pl --conf=db.conf --verbose --setline --interval=10 >>setline.log 2>&1
 ) 200>/web/scripts/atlas_auto/atlas.lock
```
测试说明:
=========

### 关闭SQL_THREAD:
```
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
```

停止ip为16的slave的复制线程后(多个端口，多个offline操作):
```
# perl atlas_auto_setline.pl --conf=db.conf --verbose --setline --threshold=30
 +---2014-04-15 11:53:01, 172.30.0.15, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 13
 +---2014-04-15 11:53:01, 172.30.0.16, Slave_IO_Running: No, Slave_SQL_Running: No, Seconds_Behind_Master: NULL
 +-- 2014-04-15 11:53:01 OK SET offline node 172.30.0.16:3306
```
atlas下线:
```
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
```

### 启动SQL_THREAD:
```
# perl atlas_auto_setline.pl --conf=db.conf --verbose --setline --threshold=30
 +---2014-04-15 11:54:01, 172.30.0.15, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
 +---2014-04-15 11:54:01, 172.30.0.16, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
 +-- 2014-04-15 11:54:01 OK SET online node 172.30.0.16:5012
```

手工offline一个节点:
===================
```
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
```

### 运行脚本使其上线:
```
# perl atlas_auto_setline.pl --conf=db.conf --verbose --setline --threshold=30
 +---2014-04-15 11:56:01, 172.30.0.15, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
 +---2014-04-15 11:56:01, 172.30.0.16, Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
 +-- 2014-04-15 11:56:01 OK SET online node 172.30.0.16:5012
```
上线成功:

循环检测
========
```
# perl atlas_auto_setline.pl --conf=db.conf --verbose --setline --threshold=30 --interval=10
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
```
说明
====

MySQL Server 版本为 5.6, 运行脚本的时候会有安全提示 ```Warning: Using a password on the command line interface can be insecure.```, 这个错误信息可以忽略, 不影响脚本的执行. perl DBI驱动不兼容atlas的管理端口, 只能通过 mysql -h 的方式调用取到结果, 5.6 的警告信息可以忽略, 也可以在my.cnf 配置里[client]设置密码信息, 然后脚本里去掉 -p$pass这部分就可以避免出现错误信息, 或使用 2>/dev/null 将错误重定向.
增加隐藏连接 MySQL 的密码信息功能, 参考文章 [safe-bash-with-mysql](http://highdb.com/%E5%A6%82%E4%BD%95%E5%AE%89%E5%85%A8%E7%9A%84%E4%BD%BF%E7%94%A8-bash-%E6%93%8D%E4%BD%9C-mysql/)
