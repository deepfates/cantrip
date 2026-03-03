---
title: "Learning loops"
url: "https://www.deepfates.com/robot-face-learning-loops"
date_fetched: "2026-02-16"
type: webpage
---

Title: Learning loops

URL Source: https://www.deepfates.com/robot-face-learning-loops

Published Time: 2020-12-29T00:00:00.000Z

Markdown Content:
_Originally published on [Robot Face](https://robotface.substack.com/p/learning-loops)._

**Previously,**

I wrote about the [learning curve](https://www.deepfates.com/robot-face-seasons-change) that artificial intelligence models use in their training, and how we can apply it to our own studies. The cyclical learning rate is raised and lowered regularly to alternate between exploring possible actions and exploiting known methods.

Another important hyperparameter in machine learning is the training time. The fewer hours it takes to train your model, the more often you can experiment with it. And deep learning models — like neural nets —are one of the few things left that can take a long time to compute.

**How long does it take to train a neural net?**

It’s highly variable. I’ve trained [image classifiers](http://legiblate.herokuapp.com/) in less than a minute, [language models](https://twitter.com/deepfates/status/1137040032571637760) for eight or ten hours, [art-generating models](https://twitter.com/deepfates/status/1332775712089104389) for days on end.

And training speed makes a real difference in the creative process: if it takes less than five minutes to train or generate, I will sit and play with it for hours. If it takes a day to train I will fuss over it for a week, fiddling with its knobs every day and leaving it to run. The three-day training run for the art generator, though… Imagine someone was running a vacuum cleaner in the next room. Not a big vacuum — but for three days. I haven’t tried a second experiment.

With machine learning you can speed up training time by reducing the complexity of your neural net or reducing the amount of training data you give it. Either way, you often trade performance for training speed. (But not always! For instance, one state of the art practice for image classifiers is “progressive resizing”, where you train the net first on very small, lo-res versions of your images, and then finetune it on progressively larger versions. This can be both better-quality and faster than training from scratch on the full-size pictures.)

However you do it, speeding up the learning process gives you faster feedback and more freedom for creativity and exploration.

**How can we apply this to a human learning process?**

One way to speed up your learning process is to review your previous thoughts at regular intervals, like a neural net testing its accuracy after every epoch. The chronological Feed of social media is not conducive to revisiting past thoughts, though. The platforms may offer little “On this day” or “Memories” features, but they’re meant to be tantalizing, not revelatory. They don’t offer insights into the development of your thoughts over time.

I’ve been using a browser extension called Thread Helper to augment this capability in myself. Thread Helper replaces the distracting “What’s Happening” panel with a list of your tweets that changes _in real time_ as you type in the “Compose Tweet” box. It surfaces thoughts from long ago for me to thread together and re-interpret in the moment. Instead of being faced with a barrage of ephemeral events and news stories, I am surrounded by my past selves and the thoughts they found it important to write down.

![Image 1](https://www.deepfates.com/images/_robotface-29861603-0.png)

I’ve been using it for a month now and it’s changed Twitter from a toy into a powerful tool. This interface is a tool for writing and thinking, rather than mindless scrolling. I could use this as my only note-taking system: threading different ideas together, expressing thoughts in small re-usable nuggets and composing them into larger essays. The power of threaded thought is just beginning to take off; for more on that, read _[The Spreading of Threading](https://aaronzlewis.com/blog/2019/05/01/spreading-threading/)_ by Aaron Z. Lewis.

Thread Helper makes Twitter into a [digital garden](https://www.deepfates.com/robot-face-digital-gardens). One of the creators of Thread Helper made this analogy explicit:

If the ground is tilted toward the present, Thread Helper pumps your attention back up to the past. It helps to grow your old thoughts into threads and tangles, rather than letting them dry up. It hydrates your memory.

In many ways the Thread Helper panel works like the Drawer from the [Artifacts design fiction](https://www.deepfates.com/robot-face-see-and-point) I wrote about last season: _it brings the information to you_. It increases the speed between having a thought and connecting it into the rest of your knowledge. It shortens your feedback loop, speeding up the learning process.

This is an actual augmentation of intelligence — artificial recall, if you will. I recommend you give [Thread Helper](https://threadhelper.com/) a try. Let me know how it works out for you.

Thanks for reading,

— deepfates

* * *
