
# Godot—GameAnalytics

July 8, 2018 – Timothy Miller <tim@webinspect.tech>

Native Asynchronous GDScript for GameAnalytics in Godot

I wanted analytics in my latest Godot game, and I wasn't able to find an adequate solution. The closest thing I could find was here on Github, [created by Montecri](https://github.com/Montecri/Godot-GameAnalytics), but it wasn't super practical. Many things were hardcoded, and when I tried adding it into my game it slowed everything down to a crawl, due to the analytics blocking the main thread whenever they submitted.

So this is my modification of his code to make things asynchronous and commercially viable. I have used this in two games so far, and the more I use it the better it gets.

This is a little repository to track my progress as I continue to refine things. The code is still fairly crude, poluted, redundant, etc, but it still works, and I think it works better than ever. It still needs a lot of work, but it's very useable already, and I still haven't spent that much time on it.

Included is a sample project that should have everything you need to get started using this library. Feel free to download and use in your own projects, and if you find ways to make things better, submit a pull request! Maybe together we can build a truly great solution for Godot and GameAnalytics.

## Useage

Simply download this project and import into Godot (currently supports v3.0.2). Everything you should need to start using the library is in the game.gd file.