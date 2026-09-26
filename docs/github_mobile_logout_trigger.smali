    :pswitch_f5
    const v1, 0x7f1304fd

    invoke-virtual {p0, v1}, Landroid/content/Context;->getString(I)Ljava/lang/String;

    move-result-object v1

    invoke-virtual {v1}, Ljava/lang/Object;->getClass()Ljava/lang/Class;

    invoke-static {p0, v1}, Lcom/github/android/activities/g;->Y(Lcom/github/android/activities/g;Ljava/lang/String;)V

    iget-object p1, p1, Lazg;->e:La5b0;

    const/4 v1, 0x6

    invoke-static {p0, p1, v0, v1}, Lcom/github/android/activities/g;->P(Lcom/github/android/activities/g;La5b0;Ldz50;I)V

    return-object v0

    nop

...

    return-void

    :cond_65
    instance-of p0, p1, Lvy60$a;

    if-eqz p0, :cond_6d

    invoke-virtual {v1, v0}, Lcom/github/android/activities/g;->Q(Lazg;)V

    return-void

    :cond_6d
    instance-of p0, p1, Lvy60$b;

    if-eqz p0, :cond_85

    const p0, 0x7f1304fd

    invoke-virtual {v1, p0}, Landroid/content/Context;->getString(I)Ljava/lang/String;

    move-result-object p0

    invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;

    invoke-static {v1, p0}, Lcom/github/android/activities/g;->Y(Lcom/github/android/activities/g;Ljava/lang/String;)V

    iget-object p0, v0, Lazg;->e:La5b0;

    const/4 p1, 0x6

    invoke-static {v1, p0, v3, p1}, Lcom/github/android/activities/g;->P(Lcom/github/android/activities/g;La5b0;Ldz50;I)V

    return-void

    :cond_85
    invoke-static {}, Lg;->d()V

    :cond_88
    :goto_88
