IRC Bouncer
===========

Introduction
------------

Ever wondered how some users on IRC appear to never sleep?
They're online, no matter the time of day.

One of the secrets to this trick is an IRC Bouncer.
This is a service which sits on an external server, and connects to IRC in your name.
You then connect to it, and can interact with IRC through it.
When you disconnect, it stays disconnected, and logs everything which happened in your absense.

IRC Bouncers are particularly handy if you have a flaky connection (meaning you drop out a lot), or you are developing a bot (you have to restart the bot a lot).

This is a little project I hacked together in a couple of days.
That said, it works pretty well, and I'm using it successfully.

Setup
-----

This isn't yet hosted on rubyforge, but it's not hard to install:

```bash
$ git clone git://github.com/canton7/irc_bouncer
$ cd irc_bouncer
$ (sudo?) rake install
```

Now start the server with `irc_bouncer start`.
**Please use a non-root user for this**.

By default, the server will run on `localhost` port `6667`.
When it's first run, it will create a `.irc_bouncer` folder in the home directory of the user it was run as, which contains a config file and a log (and some other stuff).
If you want to change the host/port it runs on, edit `~/.irc_bouncer/config.ini`, and configure it to your tastes.
Then restart the server with `irc_bouncer restart`.

First Connection
----------------

If you had a look inside `config.ini`, you'll have found not a lot.
This is because the majority of the configuration is done using IRC.

The first time you connect to the bouncer, it will create a new admin account for you.
Therefore let's set up a couple of things first.

1. Create a new IRC connection
1. Set the Server Password to a password of your choosing
1. Point the connection at `localhost` port `6667` (or your new host/port, if you changed them).

Now connect!

IRCBouncer should create you a new admin user, and tell you what it's up to.

All IRCBouncer administration is done through the `/relay` command.
Type `/relay help` for a list of available commands.

First Server
------------

So, you'd normally connect to `<your favourite IRC server>` using `/connect blah`, but you've already connected to the relay...
To tell the relay to connect to a new server, do the following:

1. `/relay create <server_name> <server_address>:<port>`
1. `/relay connect <server_name>`.

`<server_name>` is a name which you give the server, and saves you having to type out the full address all of the time.
`<server_address>` and `<port>` are the address and port of the server to connect to.
E.g. for Freenode, these might be `irc.freenode.net` and `6667`.

You can now interact with the server as normal.

You might want to change your IRC username (not nick, and not real name) to `<username>@<server_name>`.
IRCBouncer is smart enough to notice this when you connect to it, and will automatically connect you to `<server_name>`.

Connecting and Disconnecting
----------------------------

After you connect to a server once, IRCBouncer will maintain that connection when you disconnect, and will re-establish it if you restart IRCBouncer.

Additionally, IRCBouncer will remember which rooms you were connected to, and rememeber everything which happens while you're away.
When you get back, IRCBouncer will replay all of the messages to you, along with the time that they were originally sent.
It will also re-join you to all the rooms you were originally in.

To get IRCBouncer to properly disconnect from and IRC server, use `/relay quit [<server_name>]`.

If Something Goes Wrong
-----------------------

This is very much alpha software (2 days' work, come on), and is highly likely to break if you do something to it which I haven't thought of.

There's a log in `~/.irc_bouncer/irc_bouncer.output`, and you can get it to run in the foreground with `irc_bouncer start -t`.
If you want to view all of the IRC traffic wizzing backwards and forwards, set the config key `verbose` to `True`.

If you've got any questions, open an issue here and I'll be happy to have a look at it.