YOUR SITE ARCHIVE
=================

This is a complete copy of what you've written — published, scheduled,
drafted, and archived. Items in the trash are not included.

Start here
----------
index.html       Open this in a browser. It links to a readable page for every
                 post, page, book, series, collection, author, newsletter, and
                 drip email. It works offline.

Moving somewhere else
---------------------
wordpress.xml    Your posts and pages in WordPress's import format (WXR).
                 WordPress: Tools -> Import -> WordPress. Ghost and Substack
                 can both import a WordPress export file.

                 Images: upload the "media" folder to the root of your new
                 site (so files sit at yoursite.com/media/...) and the images
                 inside your posts will resolve.

subscribers/     subscribers.csv     Confirmed readers you may email. Import
                                     this as your list.
                 suppressions.csv    People who unsubscribed, bounced, or
                                     complained. Import this as a suppression
                                     (do-not-mail) list. NEVER add these
                                     addresses to your list.
                 consent_events.csv  When and how each reader opted in. Keep
                                     it: it is your proof of consent.

Everything, for a developer
---------------------------
content.json     The complete record, including what wordpress.xml has no
                 room for: books, series, newsletters (send dates and
                 results), drip sequences, and drafts of everything.

media/           Every image, at original quality.

This archive contains your readers' email addresses. Keep it somewhere safe.
