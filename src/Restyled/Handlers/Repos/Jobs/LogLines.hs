module Restyled.Handlers.Repos.Jobs.LogLines
    ( getRepoJobLogLinesR
    ) where

import Restyled.Prelude

import qualified Data.Text as T
import qualified Data.Text.Lazy as LT
import Restyled.Foundation
import Restyled.JobOutput
import Restyled.Models
import Restyled.Time
import Restyled.WebSockets
import qualified Restyled.Widgets.Job as Widgets
import Restyled.Yesod
import Text.Blaze.Html.Renderer.Text (renderHtml)

getRepoJobLogLinesR :: OwnerName -> RepoName -> JobId -> Handler Text
getRepoJobLogLinesR _owner _name jobId = do
    job <- runDB $ get404 jobId
    expired <- (jobUpdatedAt job <=) <$> getLogRetentionStart

    webSockets $ ignoringConnectionException $ unless expired $ do
        conn <- ask

        lift $ followJobOutput jobId $ \jobLogLines -> do
            htmls <- mconcat <$> traverse renderJobLogLine jobLogLines
            runReaderT (void $ sendTextDataAck htmls) conn

    -- If not accessed via WebSockets, respond with plain text Job log
    jobLogLines <- if expired then pure [] else fetchJobOutput jobId
    pure $ T.unlines $ map jobLogLineContent jobLogLines

getLogRetentionStart :: MonadIO m => m UTCTime
getLogRetentionStart = subtractTime (Days $ 30 + 5) <$> getCurrentTime

renderJobLogLine :: JobLogLine -> Handler LT.Text
renderJobLogLine ln = do
    pc <- widgetToPageContent $ Widgets.jobLogLine ln
    renderHtml <$> withUrlRenderer (pageBody pc)
