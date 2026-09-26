    :cond_1e
    invoke-direct {p0, v2}, Lcom/android/server/accounts/AccountManagerService;->getAccountsForSystem([I)[Landroid/accounts/AccountAndUser;

    move-result-object p0

    return-object p0
.end method

.method public getAuthToken(Landroid/accounts/IAccountManagerResponse;Landroid/accounts/Account;Ljava/lang/String;ZZLandroid/os/Bundle;)V
    .registers 28

    move-object/from16 v0, p0

    move-object/from16 v6, p1

    move-object/from16 v10, p2

    move-object/from16 v11, p3

    move/from16 v12, p4

    move-object/from16 v9, p6

    const/4 v1, 0x1

    .line 3177
    invoke-static {v9, v1}, Landroid/os/Bundle;->setDefusable(Landroid/os/Bundle;Z)Landroid/os/Bundle;

    .line 3178
    const-string v7, "AccountManagerService"

    const/4 v8, 0x2

    invoke-static {v7, v8}, Landroid/util/Log;->isLoggable(Ljava/lang/String;I)Z

    move-result v2

    if-eqz v2, :cond_68

    .line 3179
    new-instance v2, Ljava/lang/StringBuilder;

    invoke-direct {v2}, Ljava/lang/StringBuilder;-><init>()V

    const-string v3, "getAuthToken: "

    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v2, v10}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;

    const-string v3, ", response "

    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v2, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;

    const-string v3, ", authTokenType "

    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v2, v11}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    const-string v3, ", notifyOnAuthFailure "

    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v2, v12}, Ljava/lang/StringBuilder;->append(Z)Ljava/lang/StringBuilder;

    const-string v3, ", expectActivityLaunch "

    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    move/from16 v13, p5

    invoke-virtual {v2, v13}, Ljava/lang/StringBuilder;->append(Z)Ljava/lang/StringBuilder;

    const-string v3, ", caller\'s uid "

    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    .line 3184
    invoke-static {}, Landroid/os/Binder;->getCallingUid()I

    move-result v3

    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;

    const-string v3, ", pid "

    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    .line 3185
    invoke-static {}, Landroid/os/Binder;->getCallingPid()I

    move-result v3

    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;

    invoke-virtual {v2}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v2

    .line 3179
    invoke-static {v7, v2}, Landroid/util/Log;->v(Ljava/lang/String;Ljava/lang/String;)I

    goto :goto_6a

    :cond_68
    move/from16 v13, p5

    :goto_6a
    const/4 v2, 0x0

    if-eqz v6, :cond_6f

    move v3, v1

    goto :goto_70

    :cond_6f
    move v3, v2

    .line 3187
    :goto_70
    const-string/jumbo v4, "response cannot be null"

    invoke-static {v3, v4}, Lcom/android/internal/util/Preconditions;->checkArgument(ZLjava/lang/Object;)V

    if-eqz v11, :cond_b6

    .line 3191
    :try_start_78
    invoke-static {}, Landroid/os/SystemClock;->elapsedRealtime()J

    move-result-wide v3

    iget-wide v14, v0, Lcom/android/server/accounts/AccountManagerService;->mLastRetryTime:J

    sub-long/2addr v3, v14

    const-wide/16 v14, 0x1f4

    cmp-long v3, v3, v14

    if-gez v3, :cond_8d

    .line 3192
    iget v3, v0, Lcom/android/server/accounts/AccountManagerService;->mRetryCount:I

    add-int/2addr v3, v1

    iput v3, v0, Lcom/android/server/accounts/AccountManagerService;->mRetryCount:I

    goto :goto_8f

    :catch_8b
    move-exception v0

    goto :goto_d1

    .line 3194
    :cond_8d
    iput v2, v0, Lcom/android/server/accounts/AccountManagerService;->mRetryCount:I

    .line 3196
    :goto_8f
    invoke-static {}, Landroid/os/SystemClock;->elapsedRealtime()J

    move-result-wide v3

    iput-wide v3, v0, Lcom/android/server/accounts/AccountManagerService;->mLastRetryTime:J

    .line 3198
    iget v3, v0, Lcom/android/server/accounts/AccountManagerService;->mRetryCount:I

    const/16 v4, 0xa

    if-lt v3, v4, :cond_b6

    .line 3199
    new-instance v0, Ljava/lang/StringBuilder;

    invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V

    const-string v1, "getAuthToken too frequently: "

    invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v0, v11}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v0

    invoke-static {v7, v0}, Landroid/util/Slog;->w(Ljava/lang/String;Ljava/lang/String;)I

    .line 3200
    const-string v0, "getAuthToken too frequently"

    const/4 v1, 0x4

    invoke-interface {v6, v1, v0}, Landroid/accounts/IAccountManagerResponse;->onError(ILjava/lang/String;)V

    return-void

    :cond_b6
    const/4 v3, 0x7

    if-nez v10, :cond_c4

    .line 3207
    const-string v0, "getAuthToken called with null account"

    invoke-static {v7, v0}, Landroid/util/Slog;->w(Ljava/lang/String;Ljava/lang/String;)I

    .line 3208
    const-string v0, "account is null"

    invoke-interface {v6, v3, v0}, Landroid/accounts/IAccountManagerResponse;->onError(ILjava/lang/String;)V

    return-void

    :cond_c4
    if-nez v11, :cond_e6

    .line 3212
    const-string v0, "getAuthToken called with null authTokenType"

    invoke-static {v7, v0}, Landroid/util/Slog;->w(Ljava/lang/String;Ljava/lang/String;)I

    .line 3213
    const-string v0, "authTokenType is null"

    invoke-interface {v6, v3, v0}, Landroid/accounts/IAccountManagerResponse;->onError(ILjava/lang/String;)V
    :try_end_d0
    .catch Landroid/os/RemoteException; {:try_start_78 .. :try_end_d0} :catch_8b

    return-void

    .line 3217
    :goto_d1
    new-instance v1, Ljava/lang/StringBuilder;

    invoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V

    const-string v2, "Failed to report error back to the client."

    invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v1, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;
