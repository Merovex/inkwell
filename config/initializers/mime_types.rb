# RSS 2.0 for the public blog feed (Rails registers :atom but not :rss).
Mime::Type.register "application/rss+xml", :rss
